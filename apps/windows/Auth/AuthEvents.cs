namespace ClaudeBar.Auth;

/// <summary>
/// In-process bus the preferences window uses to tell the tray that the
/// signed-in identity has changed. Without it, the tray snapshot stays on
/// the previous "unauthenticated" value until the next poll tick (default
/// 5 min). TokenStore.Store is also called by UsageSource on token refresh,
/// so we deliberately raise from the sign-in/out call sites rather than from
/// TokenStore itself.
/// </summary>
public static class AuthEvents
{
    public static event EventHandler? Changed;

    public static void RaiseChanged() => Changed?.Invoke(null, EventArgs.Empty);
}
