// SPDX-License-Identifier: GPL-3.0-or-later
// OAuth PKCE flow — identical to the GNOME extension's implementation,
// adapted to Cinnamon's GJS import paths.

const GLib = imports.gi.GLib;
const Gio = imports.gi.Gio;
const Soup = imports.gi.Soup;

var CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
var AUTHORIZE_URL = "https://claude.ai/oauth/authorize";
var TOKEN_URL = "https://console.anthropic.com/v1/oauth/token";
var SCOPES = "user:inference user:profile";
var LOGIN_TIMEOUT_SECONDS = 300;

function randomBytes(n) {
    const stream = Gio.File.new_for_path("/dev/urandom").read(null);
    const bytes = stream.read_bytes(n, null);
    stream.close(null);
    const data = bytes.get_data();
    if (!data) throw new Error("failed to read /dev/urandom");
    return new Uint8Array(data);
}

function base64UrlEncode(bytes) {
    const b64 = GLib.base64_encode(bytes);
    return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function hexToBytes(hex) {
    const out = new Uint8Array(hex.length / 2);
    for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
    return out;
}

function sha256(input) {
    const hex = GLib.compute_checksum_for_string(GLib.ChecksumType.SHA256, input, input.length);
    if (!hex) throw new Error("sha256 failed");
    return hexToBytes(hex);
}

function generatePkce() {
    const verifier = base64UrlEncode(randomBytes(32));
    const challenge = base64UrlEncode(sha256(verifier));
    return { verifier, challenge };
}

function buildAuthorizeUrl(params) {
    const qs = Object.entries(params)
        .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
        .join("&");
    return `${AUTHORIZE_URL}?${qs}`;
}

function parseTokenResponse(text) {
    const json = JSON.parse(text);
    if (!json.access_token) throw new Error("token response missing access_token");
    return {
        access_token: json.access_token,
        refresh_token: json.refresh_token ?? null,
        expires_at: typeof json.expires_in === "number"
            ? Math.floor(Date.now() / 1000) + json.expires_in
            : null,
    };
}

function postJson(session, url, body) {
    return new Promise((resolve, reject) => {
        const msg = Soup.Message.new("POST", url);
        if (!msg) return reject(new Error(`failed to construct request for ${url}`));
        msg.get_request_headers().append("Content-Type", "application/json");
        msg.get_request_headers().append("Accept", "application/json");
        msg.set_request_body_from_bytes(
            "application/json",
            new GLib.Bytes(new TextEncoder().encode(JSON.stringify(body)))
        );
        session.send_and_read_async(msg, GLib.PRIORITY_DEFAULT, null, (_s, res) => {
            try {
                const bytes = session.send_and_read_finish(res);
                const status = msg.get_status();
                const text = new TextDecoder("utf-8").decode(bytes.get_data() ?? new Uint8Array());
                if (status < 200 || status >= 300) {
                    reject(new Error(`token endpoint returned ${status}: ${text}`));
                    return;
                }
                resolve(text);
            } catch (e) {
                reject(e);
            }
        });
    });
}

function refreshAccessToken(refreshToken) {
    const session = new Soup.Session();
    session.timeout = 15;
    return postJson(session, TOKEN_URL, {
        grant_type: "refresh_token",
        refresh_token: refreshToken,
        client_id: CLIENT_ID,
    }).then(parseTokenResponse);
}

function startLoginFlow() {
    const { verifier, challenge } = generatePkce();
    const state = base64UrlEncode(randomBytes(24));
    const server = new Soup.Server({});
    server.listen_local(0, Soup.ServerListenOptions.IPV4_ONLY);
    const uris = server.get_uris();
    if (!uris || uris.length === 0) throw new Error("failed to bind loopback listener");
    const port = uris[0].get_port();
    const redirectUri = `http://localhost:${port}/callback`;

    const authorizeUrl = buildAuthorizeUrl({
        client_id: CLIENT_ID,
        response_type: "code",
        redirect_uri: redirectUri,
        scope: SCOPES,
        code_challenge: challenge,
        code_challenge_method: "S256",
        state,
    });

    let cleaned = false;
    let timeoutId = 0;
    const cleanup = () => {
        if (cleaned) return;
        cleaned = true;
        if (timeoutId) {
            GLib.source_remove(timeoutId);
            timeoutId = 0;
        }
        try { server.disconnect(); } catch (_e) { /* noop */ }
    };

    const result = new Promise((resolve, reject) => {
        timeoutId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, LOGIN_TIMEOUT_SECONDS, () => {
            cleanup();
            reject(new Error("sign-in timed out"));
            return GLib.SOURCE_REMOVE;
        });

        server.add_handler("/callback", (_server, msg, _path, query) => {
            try {
                const err = query?.error;
                if (err) {
                    const errDesc = query?.error_description ?? "";
                    respond(msg, 400, `Sign-in failed: ${err}. ${errDesc}`);
                    cleanup();
                    reject(new Error(`oauth error: ${err} ${errDesc}`));
                    return;
                }
                const rawCode = query?.code;
                if (!rawCode) {
                    respond(msg, 400, "Missing authorization code.");
                    cleanup();
                    reject(new Error("oauth callback missing code"));
                    return;
                }

                let code = rawCode;
                let returnedState = query?.state;
                const hashIdx = rawCode.indexOf("#");
                if (hashIdx >= 0) {
                    code = rawCode.slice(0, hashIdx);
                    if (!returnedState) returnedState = rawCode.slice(hashIdx + 1);
                }

                if (returnedState && returnedState !== state) {
                    respond(msg, 400, "State mismatch.");
                    cleanup();
                    reject(new Error("oauth state mismatch"));
                    return;
                }

                respond(msg, 200, "Signed in. You can close this tab and return to the Cinnamon applet.");

                const session = new Soup.Session();
                session.timeout = 15;
                const body = {
                    grant_type: "authorization_code",
                    code,
                    client_id: CLIENT_ID,
                    redirect_uri: redirectUri,
                    code_verifier: verifier,
                };
                if (returnedState) body.state = returnedState;

                postJson(session, TOKEN_URL, body)
                    .then((text) => { cleanup(); resolve(parseTokenResponse(text)); })
                    .catch((e) => { cleanup(); reject(e); });
            } catch (e) {
                cleanup();
                reject(e);
            }
        });
    });

    return { authorizeUrl, result, cancel: cleanup };
}

function respond(msg, status, body) {
    const html = `<!doctype html><html><head><meta charset="utf-8"><title>claudebar</title>
<style>body{font-family:system-ui,sans-serif;padding:48px;max-width:480px;margin:auto;color:#222}</style>
</head><body><h2>claudebar</h2><p>${body}</p></body></html>`;
    const bytes = new GLib.Bytes(new TextEncoder().encode(html));
    msg.get_response_headers().replace("Content-Type", "text/html; charset=utf-8");
    msg.get_response_body().append_bytes(bytes);
    msg.set_status(status, null);
}
