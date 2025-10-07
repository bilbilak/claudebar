//! OAuth PKCE flow with a loopback HTTP listener, mirroring the GNOME extension.

use anyhow::{anyhow, bail, Context, Result};
use base64::Engine;
use gettextrs::gettext;
use rand::RngCore;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::process::{Command, Stdio};
use std::time::Duration;

use crate::auth::Tokens;

const CLIENT_ID: &str = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
const AUTHORIZE_URL: &str = "https://claude.ai/oauth/authorize";
const TOKEN_URL: &str = "https://console.anthropic.com/v1/oauth/token";
const SCOPES: &str = "user:inference user:profile";
const LOGIN_TIMEOUT_SECS: u64 = 300;

#[derive(Debug, serde::Deserialize)]
struct TokenResponse {
    access_token: Option<String>,
    refresh_token: Option<String>,
    expires_in: Option<i64>,
}

pub fn run_login_flow() -> Result<Tokens> {
    let verifier = pkce_verifier();
    let challenge = pkce_challenge(&verifier);
    let state = random_base64url(24);

    let listener = TcpListener::bind("127.0.0.1:0").context("binding loopback listener")?;
    listener
        .set_nonblocking(false)
        .context("setting listener to blocking mode")?;
    let port = listener.local_addr().context("reading bound port")?.port();
    let redirect_uri = format!("http://localhost:{port}/callback");

    let authorize = build_authorize_url(&redirect_uri, &challenge, &state);

    // Best-effort: copy the URL to the clipboard and ping the user via the
    // desktop notification daemon before launching the browser. Front-ends
    // that spawn this helper from a panel menu have no surface area to show
    // the link inline (GTK/Qt/QML menus dismiss on click), so this is the
    // shared fallback path: if the wrong browser auto-opens, the user can
    // paste the link into the right one. Both are best-effort and silently
    // skipped if the tools/daemon are missing.
    copy_to_clipboard(&authorize);
    show_signin_notification();

    eprintln!("{}", gettext("Opening browser for sign-in…"));
    if webbrowser::open(&authorize).is_err() {
        // %s is the authorize URL; translations must keep the placeholder.
        eprintln!(
            "{}",
            gettext("Could not launch a browser automatically. Open this URL manually:\n\n  %s\n")
                .replace("%s", &authorize)
        );
    } else {
        eprintln!(
            "{}",
            gettext("If nothing opens, paste this URL in a browser:\n\n  %s\n")
                .replace("%s", &authorize)
        );
    }

    listener
        .set_nonblocking(true)
        .context("setting listener non-blocking for polling")?;
    let deadline = std::time::Instant::now() + Duration::from_secs(LOGIN_TIMEOUT_SECS);

    loop {
        match listener.accept() {
            Ok((stream, _)) => {
                if let Some(callback) = handle_callback(stream, &state)? {
                    return exchange_code(
                        &callback.code,
                        callback.state.as_deref(),
                        &redirect_uri,
                        &verifier,
                    );
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                if std::time::Instant::now() >= deadline {
                    bail!(
                        "{}",
                        gettext("Sign-in timed out after %d seconds").replacen(
                            "%d",
                            &LOGIN_TIMEOUT_SECS.to_string(),
                            1
                        )
                    );
                }
                std::thread::sleep(Duration::from_millis(200));
            }
            Err(e) => return Err(e).context("accepting loopback connection"),
        }
    }
}

pub fn refresh_access_token(refresh_token: &str) -> Result<Tokens> {
    let body = serde_json::json!({
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": CLIENT_ID,
    });
    post_token(&body)
}

struct Callback {
    code: String,
    state: Option<String>,
}

fn handle_callback(
    mut stream: std::net::TcpStream,
    expected_state: &str,
) -> Result<Option<Callback>> {
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .context("setting stream read timeout")?;
    stream
        .set_write_timeout(Some(Duration::from_secs(5)))
        .context("setting stream write timeout")?;

    let mut buf = [0u8; 8192];
    let n = match stream.read(&mut buf) {
        Ok(n) => n,
        Err(_) => {
            respond(&mut stream, 400, &gettext("Bad request.")).ok();
            return Ok(None);
        }
    };
    if n == 0 {
        return Ok(None);
    }
    let request = String::from_utf8_lossy(&buf[..n]);
    let first_line = request.split("\r\n").next().unwrap_or("");
    let mut parts = first_line.split_whitespace();
    let _method = parts.next();
    let target = parts.next().unwrap_or("");

    if !target.starts_with("/callback") {
        respond(&mut stream, 404, &gettext("Not found.")).ok();
        return Ok(None);
    }

    let query = target.split_once('?').map(|(_, q)| q).unwrap_or("");
    let params = parse_query(query);

    if let Some(err) = params.get("error") {
        let desc = params.get("error_description").cloned().unwrap_or_default();
        // Match auth_sign_in_failed in i18n/strings.yaml ("Sign-in failed").
        let msg = format!("{}: {err}. {desc}", gettext("Sign-in failed"));
        respond(&mut stream, 400, &msg).ok();
        bail!("oauth provider returned error: {err} {desc}");
    }

    let Some(raw_code) = params.get("code") else {
        respond(&mut stream, 400, &gettext("Missing authorization code.")).ok();
        bail!("oauth callback missing code");
    };

    let (code, returned_state) = match raw_code.split_once('#') {
        Some((c, s)) => (c.to_string(), Some(s.to_string())),
        None => (raw_code.clone(), params.get("state").cloned()),
    };

    if let Some(s) = returned_state.as_deref() {
        if !s.is_empty() && s != expected_state {
            respond(&mut stream, 400, &gettext("State mismatch.")).ok();
            bail!("oauth state mismatch");
        }
    }

    respond(
        &mut stream,
        200,
        &gettext("Signed in. You can close this tab and return to claudebar."),
    )
    .ok();

    Ok(Some(Callback {
        code,
        state: returned_state,
    }))
}

fn respond(stream: &mut std::net::TcpStream, code: u16, message: &str) -> Result<()> {
    let status_text = match code {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        _ => "OK",
    };
    let body = format!(
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>claudebar</title>\
<style>body{{font-family:system-ui,sans-serif;padding:48px;max-width:480px;margin:auto;color:#222}}</style>\
</head><body><h2>claudebar</h2><p>{}</p></body></html>",
        html_escape(message)
    );
    let response = format!(
        "HTTP/1.1 {code} {status_text}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {len}\r\nConnection: close\r\n\r\n{body}",
        len = body.len()
    );
    stream
        .write_all(response.as_bytes())
        .context("writing HTTP response")?;
    stream.flush().ok();
    Ok(())
}

fn exchange_code(
    code: &str,
    state: Option<&str>,
    redirect_uri: &str,
    verifier: &str,
) -> Result<Tokens> {
    let mut body = serde_json::json!({
        "grant_type": "authorization_code",
        "code": code,
        "client_id": CLIENT_ID,
        "redirect_uri": redirect_uri,
        "code_verifier": verifier,
    });
    if let Some(s) = state {
        body["state"] = serde_json::Value::String(s.to_string());
    }
    post_token(&body)
}

fn post_token(body: &serde_json::Value) -> Result<Tokens> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent("claudebar-helper/0.1")
        .build()
        .context("building HTTP client")?;

    let resp = client
        .post(TOKEN_URL)
        .json(body)
        .header("Accept", "application/json")
        .send()
        .context("sending token exchange request")?;
    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        bail!(
            "token endpoint returned {}: {}",
            status.as_u16(),
            truncate(&text, 300)
        );
    }
    let parsed: TokenResponse = serde_json::from_str(&text).map_err(|e| {
        anyhow!(
            "token response was not valid JSON: {e}; body={}",
            truncate(&text, 300)
        )
    })?;
    let access = parsed
        .access_token
        .ok_or_else(|| anyhow!("token response missing access_token"))?;
    let expires_at = parsed
        .expires_in
        .map(|s| chrono::Utc::now().timestamp() + s);
    Ok(Tokens {
        access_token: access,
        refresh_token: parsed.refresh_token,
        expires_at,
    })
}

fn build_authorize_url(redirect_uri: &str, challenge: &str, state: &str) -> String {
    let pairs: Vec<(&str, String)> = vec![
        ("client_id", CLIENT_ID.to_string()),
        ("response_type", "code".into()),
        ("redirect_uri", redirect_uri.to_string()),
        ("scope", SCOPES.to_string()),
        ("code_challenge", challenge.to_string()),
        ("code_challenge_method", "S256".into()),
        ("state", state.to_string()),
    ];

    let qs = pairs
        .into_iter()
        .map(|(k, v)| format!("{}={}", urlencoding::encode(k), urlencoding::encode(&v)))
        .collect::<Vec<_>>()
        .join("&");
    format!("{AUTHORIZE_URL}?{qs}")
}

fn parse_query(q: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    if q.is_empty() {
        return out;
    }
    for pair in q.split('&') {
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        let k = urlencoding::decode(k)
            .map(|s| s.into_owned())
            .unwrap_or_else(|_| k.to_string());
        let v = urlencoding::decode(v)
            .map(|s| s.into_owned())
            .unwrap_or_else(|_| v.to_string());
        out.insert(k, v);
    }
    out
}

fn pkce_verifier() -> String {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    base64_url(&bytes)
}

fn pkce_challenge(verifier: &str) -> String {
    let digest = Sha256::digest(verifier.as_bytes());
    base64_url(&digest)
}

fn random_base64url(n: usize) -> String {
    let mut bytes = vec![0u8; n];
    rand::thread_rng().fill_bytes(&mut bytes);
    base64_url(&bytes)
}

fn base64_url(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}…", &s[..max])
    }
}

/// Pipe `text` into a command's stdin via `Command::spawn`. Returns `true`
/// only if spawn succeeded *and* the child exited with status 0.
fn pipe_into(cmd: &str, args: &[&str], text: &str) -> bool {
    let mut child = match Command::new(cmd)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(c) => c,
        Err(_) => return false,
    };
    if let Some(mut stdin) = child.stdin.take() {
        if stdin.write_all(text.as_bytes()).is_err() {
            return false;
        }
    }
    matches!(child.wait(), Ok(s) if s.success())
}

/// Copy `text` to the system clipboard, trying Wayland first on Wayland
/// sessions, then common X11 helpers (which also work under XWayland).
/// Silent no-op if none are installed — the browser still opens, so the
/// user is no worse off than before.
fn copy_to_clipboard(text: &str) {
    let on_wayland = std::env::var_os("WAYLAND_DISPLAY").is_some();
    if on_wayland && pipe_into("wl-copy", &[], text) {
        return;
    }
    if pipe_into("xclip", &["-selection", "clipboard"], text) {
        return;
    }
    let _ = pipe_into("xsel", &["--clipboard", "--input"], text);
}

/// Fire-and-forget desktop notification via `notify-send`. Title is the
/// brand; body comes from the i18n catalog. Silent no-op when libnotify-bin
/// (the package owning `notify-send`) isn't installed.
fn show_signin_notification() {
    // Match auth_link_copied_notify in i18n/strings.yaml.
    let body = gettext("Sign-in link copied to clipboard");
    let _ = Command::new("notify-send")
        .args([
            "--app-name=claudebar",
            "--icon=claudebar",
            "--expire-time=4000",
            "ClaudeBar",
            &body,
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}
