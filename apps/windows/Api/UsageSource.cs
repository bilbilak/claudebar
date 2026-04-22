using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using ClaudeBar.Auth;

namespace ClaudeBar.Api;

public sealed class UsageSource
{
    private const string UsageUrl = "https://api.anthropic.com/api/oauth/usage";
    private const string AnthropicBeta = "oauth-2025-04-20";

    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        c.DefaultRequestHeaders.UserAgent.ParseAdd("claudebar-windows/0.1");
        return c;
    }

    public async Task<UsageSnapshot> FetchAsync(CancellationToken ct = default)
    {
        var tokens = TokenStore.Load();
        if (tokens is null)
            return UsageSnapshot.Empty(UsageStatus.Unauthenticated);

        var (result, body) = await CallAsync(tokens.AccessToken, ct);

        if (result == CallResult.Unauthorized && !string.IsNullOrEmpty(tokens.RefreshToken))
        {
            try
            {
                var refreshed = await OAuth.RefreshAsync(tokens.RefreshToken!, ct);
                TokenStore.Store(refreshed);
                (result, body) = await CallAsync(refreshed.AccessToken, ct);
            }
            catch
            {
                return UsageSnapshot.Empty(UsageStatus.Unauthenticated);
            }
        }

        return result switch
        {
            CallResult.Ok => Map(body!),
            CallResult.Unauthorized => UsageSnapshot.Empty(UsageStatus.Unauthenticated),
            CallResult.RateLimited => UsageSnapshot.Empty(UsageStatus.RateLimited),
            _ => UsageSnapshot.Empty(UsageStatus.Offline),
        };
    }

    private static UsageSnapshot Map(string body)
    {
        using var doc = JsonDocument.Parse(body);
        var root = doc.RootElement;
        return new UsageSnapshot(
            ParseBucket(root, "five_hour"),
            ParseBucket(root, "seven_day"),
            UsageStatus.Ok,
            DateTimeOffset.UtcNow);
    }

    private static UsageBucket ParseBucket(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var e) || e.ValueKind != JsonValueKind.Object)
            return new UsageBucket(0, null);

        double pct = 0;
        if (e.TryGetProperty("utilization", out var u))
        {
            if (u.ValueKind == JsonValueKind.Number && u.TryGetDouble(out var d))
                pct = d;
        }

        DateTimeOffset? at = null;
        if (e.TryGetProperty("resets_at", out var r) && r.ValueKind == JsonValueKind.String)
        {
            if (DateTimeOffset.TryParse(r.GetString(),
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal,
                out var parsed))
            {
                at = parsed;
            }
        }
        return new UsageBucket(pct, at);
    }

    private enum CallResult { Ok, Unauthorized, RateLimited, Offline }

    private static async Task<(CallResult, string?)> CallAsync(string token, CancellationToken ct)
    {
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, UsageUrl);
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            req.Headers.Add("anthropic-beta", AnthropicBeta);
            req.Headers.Accept.ParseAdd("application/json");

            using var resp = await Http.SendAsync(req, ct);
            var code = (int)resp.StatusCode;
            if (code >= 200 && code < 300)
            {
                var text = await resp.Content.ReadAsStringAsync(ct);
                return (CallResult.Ok, text);
            }
            if (code == 401) return (CallResult.Unauthorized, null);
            if (code == 429) return (CallResult.RateLimited, null);
            return (CallResult.Offline, null);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return (CallResult.Offline, null);
        }
    }
}
