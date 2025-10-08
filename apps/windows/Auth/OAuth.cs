using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ClaudeBar.Auth;

public static class OAuth
{
    public const string ClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
    public const string AuthorizeUrl = "https://claude.ai/oauth/authorize";
    public const string TokenUrl = "https://console.anthropic.com/v1/oauth/token";
    public const string Scopes = "user:inference user:profile";
    public static readonly TimeSpan LoginTimeout = TimeSpan.FromMinutes(5);

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    public sealed class LoginFlow : IDisposable
    {
        private readonly LoopbackOAuthServer _server;
        private readonly string _verifier;
        private readonly string _redirectUri;
        private readonly CancellationTokenSource _cts = new();
        private int _disposed;

        public string AuthorizeUri { get; }

        internal LoginFlow(LoopbackOAuthServer server, string verifier, string authorizeUri, string redirectUri)
        {
            _server = server;
            _verifier = verifier;
            _redirectUri = redirectUri;
            AuthorizeUri = authorizeUri;
        }

        public async Task<TokenSet> AwaitResultAsync()
        {
            try
            {
                var callback = await _server.WaitForCodeAsync(LoginTimeout, _cts.Token);
                var body = new Dictionary<string, string>
                {
                    ["grant_type"] = "authorization_code",
                    ["code"] = callback.Code,
                    ["client_id"] = ClientId,
                    ["redirect_uri"] = _redirectUri,
                    ["code_verifier"] = _verifier,
                };
                if (!string.IsNullOrEmpty(callback.State)) body["state"] = callback.State!;
                return await ExchangeAsync(body);
            }
            finally
            {
                Dispose();
            }
        }

        public void Cancel()
        {
            try { _cts.Cancel(); } catch { /* ignored */ }
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
            try { _cts.Cancel(); } catch { }
            _server.Dispose();
            _cts.Dispose();
        }
    }

    public static LoginFlow StartLogin()
    {
        var verifier = PkceVerifier();
        var challenge = PkceChallenge(verifier);
        var state = RandomBase64Url(24);
        var server = new LoopbackOAuthServer(state);
        var redirectUri = $"http://localhost:{server.Port}/callback";

        var qs = new (string k, string v)[]
        {
            ("client_id", ClientId),
            ("response_type", "code"),
            ("redirect_uri", redirectUri),
            ("scope", Scopes),
            ("code_challenge", challenge),
            ("code_challenge_method", "S256"),
            ("state", state),
        };
        var sb = new StringBuilder();
        for (int i = 0; i < qs.Length; i++)
        {
            if (i > 0) sb.Append('&');
            sb.Append(Uri.EscapeDataString(qs[i].k));
            sb.Append('=');
            sb.Append(Uri.EscapeDataString(qs[i].v));
        }
        var authorizeUri = $"{AuthorizeUrl}?{sb}";
        return new LoginFlow(server, verifier, authorizeUri, redirectUri);
    }

    public static async Task<TokenSet> RefreshAsync(string refreshToken, CancellationToken ct = default)
    {
        var body = new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = refreshToken,
            ["client_id"] = ClientId,
        };
        return await ExchangeAsync(body, ct);
    }

    private static async Task<TokenSet> ExchangeAsync(Dictionary<string, string> body, CancellationToken ct = default)
    {
        var json = JsonSerializer.Serialize(body);
        using var req = new HttpRequestMessage(HttpMethod.Post, TokenUrl)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
        req.Headers.Accept.ParseAdd("application/json");

        using var resp = await Http.SendAsync(req, ct);
        var text = await resp.Content.ReadAsStringAsync(ct);
        if (!resp.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"token endpoint returned {(int)resp.StatusCode}: {Truncate(text, 300)}");
        }
        return ParseTokenResponse(text);
    }

    private static TokenSet ParseTokenResponse(string text)
    {
        using var doc = JsonDocument.Parse(text);
        var root = doc.RootElement;
        var access = root.TryGetProperty("access_token", out var a) && a.ValueKind == JsonValueKind.String
            ? a.GetString()
            : null;
        if (string.IsNullOrEmpty(access))
            throw new InvalidOperationException("token response missing access_token");

        var refresh = root.TryGetProperty("refresh_token", out var r) && r.ValueKind == JsonValueKind.String
            ? r.GetString()
            : null;

        long? expiresAt = null;
        if (root.TryGetProperty("expires_in", out var e) && e.ValueKind == JsonValueKind.Number && e.TryGetInt64(out var sec))
        {
            expiresAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds() + sec;
        }
        return new TokenSet(access!, refresh, expiresAt);
    }

    private static string PkceVerifier()
    {
        var bytes = RandomNumberGenerator.GetBytes(32);
        return Base64Url(bytes);
    }

    private static string PkceChallenge(string verifier)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(verifier));
        return Base64Url(hash);
    }

    private static string RandomBase64Url(int bytes)
    {
        var b = RandomNumberGenerator.GetBytes(bytes);
        return Base64Url(b);
    }

    private static string Base64Url(byte[] data) =>
        Convert.ToBase64String(data).Replace('+', '-').Replace('/', '_').TrimEnd('=');

    private static string Truncate(string s, int max) =>
        s.Length <= max ? s : s[..max] + "…";
}

/// <summary>
/// Minimal loopback HTTP listener that waits for the OAuth redirect on an ephemeral port.
/// </summary>
internal sealed class LoopbackOAuthServer : IDisposable
{
    private readonly TcpListener _listener;
    private readonly string _expectedState;
    private int _disposed;

    public int Port { get; }

    public LoopbackOAuthServer(string expectedState)
    {
        _expectedState = expectedState;
        _listener = new TcpListener(IPAddress.Loopback, 0);
        _listener.Start();
        Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
    }

    public async Task<Callback> WaitForCodeAsync(TimeSpan timeout, CancellationToken ct)
    {
        using var timeoutCts = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct, timeoutCts.Token);
        var lct = linked.Token;

        while (!lct.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await _listener.AcceptTcpClientAsync(lct);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            using (client)
            {
                using var stream = client.GetStream();
                stream.ReadTimeout = 5000;
                stream.WriteTimeout = 5000;

                var buffer = new byte[8192];
                int n;
                try
                {
                    n = await stream.ReadAsync(buffer, lct);
                }
                catch
                {
                    continue;
                }
                if (n <= 0) continue;

                var request = Encoding.UTF8.GetString(buffer, 0, n);
                var (method, target) = ParseRequestLine(request);
                if (method is null || target is null)
                {
                    await RespondAsync(stream, 400, "Bad request.", lct);
                    continue;
                }

                if (!target.StartsWith("/callback", StringComparison.Ordinal))
                {
                    await RespondAsync(stream, 404, "Not found.", lct);
                    continue;
                }

                var qIdx = target.IndexOf('?');
                var query = qIdx >= 0 ? target[(qIdx + 1)..] : "";
                var parsed = ParseQuery(query);

                if (parsed.TryGetValue("error", out var err))
                {
                    parsed.TryGetValue("error_description", out var desc);
                    await RespondAsync(stream, 400, $"Sign-in failed: {err}. {desc}", lct);
                    throw new InvalidOperationException($"oauth error: {err} {desc}");
                }

                if (!parsed.TryGetValue("code", out var rawCode) || string.IsNullOrEmpty(rawCode))
                {
                    await RespondAsync(stream, 400, "Missing authorization code.", lct);
                    throw new InvalidOperationException("oauth callback missing code");
                }

                var code = rawCode;
                parsed.TryGetValue("state", out var returnedState);
                var hashIdx = rawCode.IndexOf('#');
                if (hashIdx >= 0)
                {
                    code = rawCode[..hashIdx];
                    if (string.IsNullOrEmpty(returnedState))
                        returnedState = rawCode[(hashIdx + 1)..];
                }

                if (!string.IsNullOrEmpty(returnedState) && returnedState != _expectedState)
                {
                    await RespondAsync(stream, 400, "State mismatch.", lct);
                    throw new InvalidOperationException("oauth state mismatch");
                }

                await RespondAsync(stream, 200, "Signed in. You can close this tab and return to ClaudeBar.", lct);
                return new Callback(code, string.IsNullOrEmpty(returnedState) ? null : returnedState);
            }
        }

        if (ct.IsCancellationRequested) throw new OperationCanceledException(ct);
        throw new TimeoutException("sign-in timed out");
    }

    private static (string? method, string? target) ParseRequestLine(string request)
    {
        var idx = request.IndexOf("\r\n", StringComparison.Ordinal);
        var first = idx >= 0 ? request[..idx] : request;
        var parts = first.Split(' ');
        if (parts.Length < 2) return (null, null);
        return (parts[0], parts[1]);
    }

    private static Dictionary<string, string> ParseQuery(string s)
    {
        var dict = new Dictionary<string, string>(StringComparer.Ordinal);
        if (string.IsNullOrEmpty(s)) return dict;
        foreach (var pair in s.Split('&', StringSplitOptions.None))
        {
            if (pair.Length == 0) continue;
            var eq = pair.IndexOf('=');
            string key, value;
            if (eq < 0)
            {
                key = WebUtility.UrlDecode(pair);
                value = "";
            }
            else
            {
                key = WebUtility.UrlDecode(pair[..eq]);
                value = WebUtility.UrlDecode(pair[(eq + 1)..]);
            }
            dict[key] = value;
        }
        return dict;
    }

    private static async Task RespondAsync(NetworkStream stream, int code, string message, CancellationToken ct)
    {
        var statusText = code switch
        {
            200 => "OK",
            400 => "Bad Request",
            404 => "Not Found",
            _ => "OK",
        };
        var escaped = WebUtility.HtmlEncode(message);
        var html =
            "<!doctype html><html><head><meta charset=\"utf-8\"><title>ClaudeBar</title>" +
            "<style>body{font-family:system-ui,sans-serif;padding:48px;max-width:480px;margin:auto;color:#222}</style>" +
            $"</head><body><h2>ClaudeBar</h2><p>{escaped}</p></body></html>";
        var body = Encoding.UTF8.GetBytes(html);
        var header = $"HTTP/1.1 {code} {statusText}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n";
        var hdrBytes = Encoding.ASCII.GetBytes(header);
        await stream.WriteAsync(hdrBytes, ct);
        await stream.WriteAsync(body, ct);
        await stream.FlushAsync(ct);
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
        try { _listener.Stop(); } catch { /* ignored */ }
    }

    public sealed record Callback(string Code, string? State);
}
