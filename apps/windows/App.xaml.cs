using System.Globalization;
using System.Windows;
using System.Windows.Markup;
using ClaudeBar.UI;

namespace ClaudeBar;

public partial class App : Application
{
    // Per-user named mutex — auto-start runs us under the same account, so
    // a Local\ scope (the default for unprefixed names) is sufficient.
    // A duplicate launch (e.g. user clicks the Start Menu shortcut while
    // the auto-start instance is already in the tray) finds the mutex
    // already held and exits silently rather than spawning a second tray
    // icon and a second poll loop.
    private const string SingleInstanceMutexName = "Bilbilak.ClaudeBar.SingleInstance";

    private TrayIconManager? _tray;
    private Mutex? _instanceMutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        _instanceMutex = new Mutex(initiallyOwned: true, SingleInstanceMutexName, out var isFirstInstance);
        if (!isFirstInstance)
        {
            // We never acquired ownership — drop the reference (we can't
            // release a mutex we don't own) and exit before any UI work.
            _instanceMutex = null;
            Shutdown();
            return;
        }

        ApplyUiCulture();

        base.OnStartup(e);
        _tray = new TrayIconManager();
    }

    /// <summary>
    /// Pin the current thread's UI culture and tell WPF to use the same
    /// language for xml:lang on FrameworkElement, so that font fallback for
    /// CJK / Arabic / Hindi picks the correct shaping engine.
    /// </summary>
    private static void ApplyUiCulture()
    {
        var culture = CultureInfo.CurrentUICulture;
        Thread.CurrentThread.CurrentUICulture = culture;
        try
        {
            FrameworkElement.LanguageProperty.OverrideMetadata(
                typeof(FrameworkElement),
                new FrameworkPropertyMetadata(
                    XmlLanguage.GetLanguage(culture.IetfLanguageTag)));
        }
        catch (ArgumentException)
        {
            // OverrideMetadata throws if it's already been set (e.g. test
            // harness re-entering OnStartup). Safe to ignore.
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        _tray = null;
        if (_instanceMutex is not null)
        {
            try { _instanceMutex.ReleaseMutex(); }
            catch (ApplicationException) { /* not owned — fine */ }
            _instanceMutex.Dispose();
            _instanceMutex = null;
        }
        base.OnExit(e);
    }
}
