using System.Windows;

namespace ClaudeBar;

public partial class App : Application
{
    private TrayIconManager? _tray;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _tray = new TrayIconManager();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        _tray = null;
        base.OnExit(e);
    }
}
