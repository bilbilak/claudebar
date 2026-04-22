using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using ClaudeBar.Api;
using ClaudeBar.Settings;
using H.NotifyIcon;

namespace ClaudeBar.UI;

public sealed class TrayIconManager : IDisposable
{
    private readonly TaskbarIcon _tray;
    private readonly UsageSource _source = new();
    private readonly DispatcherTimer _timer;

    private UsageSnapshot? _snapshot;
    private bool _refreshInFlight;
    private PreferencesWindow? _prefsWindow;
    private FloatingMeterWindow? _floatingMeter;
    private int _disposed;

    private readonly MenuItem _sessionItem = new() { Header = "Current session: —", IsEnabled = false, StaysOpenOnClick = true };
    private readonly MenuItem _sessionReset = new() { Header = "", IsEnabled = false, StaysOpenOnClick = true };
    private readonly MenuItem _weeklyItem = new() { Header = "Weekly (all models): —", IsEnabled = false, StaysOpenOnClick = true };
    private readonly MenuItem _weeklyReset = new() { Header = "", IsEnabled = false, StaysOpenOnClick = true };
    private readonly MenuItem _statusLine = new() { Header = "", IsEnabled = false, Visibility = Visibility.Collapsed, StaysOpenOnClick = true };

    public TrayIconManager()
    {
        _tray = new TaskbarIcon
        {
            ToolTipText = "ClaudeBar",
            NoLeftClickDelay = true,
        };
        BuildMenu();
        UpdateIcon();

        _timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(Math.Max(60, SettingsStore.Instance.PollInterval)),
        };
        _timer.Tick += (_, _) => _ = RefreshAsync();
        _timer.Start();

        SettingsStore.Instance.PropertyChanged += OnSettingsChanged;

        SyncFloatingMeter();
        _ = RefreshAsync();
    }

    private void SyncFloatingMeter()
    {
        var s = SettingsStore.Instance;
        if (s.FloatingMeterEnabled)
        {
            if (_floatingMeter is null)
            {
                _floatingMeter = new FloatingMeterWindow();
                _floatingMeter.RefreshRequested += (_, _) => _ = RefreshAsync();
                _floatingMeter.PrefsRequested += (_, _) => ShowPreferences();
                _floatingMeter.HideRequested += (_, _) =>
                {
                    SettingsStore.Instance.FloatingMeterEnabled = false;
                };
                _floatingMeter.SetSnapshot(_snapshot);
                _floatingMeter.Show();
            }
        }
        else if (_floatingMeter is not null)
        {
            try { _floatingMeter.Close(); } catch { /* ignored */ }
            _floatingMeter = null;
        }
    }

    private void BuildMenu()
    {
        var menu = new ContextMenu();

        var header = new MenuItem
        {
            Header = "ClaudeBar",
            FontWeight = FontWeights.Bold,
            IsEnabled = false,
            StaysOpenOnClick = true,
        };
        menu.Items.Add(header);
        menu.Items.Add(new Separator());
        menu.Items.Add(_sessionItem);
        menu.Items.Add(_sessionReset);
        menu.Items.Add(_weeklyItem);
        menu.Items.Add(_weeklyReset);
        menu.Items.Add(_statusLine);
        menu.Items.Add(new Separator());

        var refresh = new MenuItem { Header = "Refresh now" };
        refresh.Click += (_, _) => _ = RefreshAsync();
        menu.Items.Add(refresh);

        var open = new MenuItem { Header = "Open claude.ai/settings/usage" };
        open.Click += (_, _) =>
        {
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "https://claude.ai/settings/usage",
                    UseShellExecute = true,
                });
            }
            catch { /* best effort */ }
        };
        menu.Items.Add(open);

        var prefs = new MenuItem { Header = "Settings…" };
        prefs.Click += (_, _) => ShowPreferences();
        menu.Items.Add(prefs);

        menu.Items.Add(new Separator());
        var quit = new MenuItem { Header = "Quit ClaudeBar" };
        quit.Click += (_, _) => Application.Current.Shutdown();
        menu.Items.Add(quit);

        _tray.ContextMenu = menu;

        // Left-click on the tray icon also opens the menu, mirroring indicator-style UX.
        _tray.LeftClickCommand = new RelayCommand(_ => OpenContextMenu());
    }

    private void OpenContextMenu()
    {
        if (_tray.ContextMenu is { } cm)
        {
            cm.Placement = System.Windows.Controls.Primitives.PlacementMode.Mouse;
            cm.IsOpen = true;
        }
    }

    private void ShowPreferences()
    {
        if (_prefsWindow is null)
        {
            _prefsWindow = new PreferencesWindow();
            _prefsWindow.Closed += (_, _) => _prefsWindow = null;
        }
        _prefsWindow.Show();
        _prefsWindow.Activate();
        _prefsWindow.Topmost = true;
        _prefsWindow.Topmost = false;
    }

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        _timer.Interval = TimeSpan.FromSeconds(Math.Max(60, SettingsStore.Instance.PollInterval));
        UpdateIcon();
        if (e.PropertyName == nameof(SettingsStore.FloatingMeterEnabled))
        {
            SyncFloatingMeter();
        }
    }

    private async Task RefreshAsync()
    {
        if (_refreshInFlight) return;
        _refreshInFlight = true;
        try
        {
            var snap = await _source.FetchAsync();
            _snapshot = snap;
            UpdateIcon();
            UpdateMenuLabels();
            UpdateToolTip();
            _floatingMeter?.SetSnapshot(snap);
        }
        finally
        {
            _refreshInFlight = false;
        }
    }

    private void UpdateIcon()
    {
        _tray.IconSource = UsageIconRenderer.Render(_snapshot, SettingsStore.Instance);
    }

    private void UpdateMenuLabels()
    {
        var s = _snapshot;
        if (s is null) return;
        _sessionItem.Header = $"Current session: {s.Session.Percent:F0}%";
        _sessionReset.Header = $"Resets {FormatReset(s.Session.ResetsAt)}";
        _weeklyItem.Header = $"Weekly (all models): {s.Weekly.Percent:F0}%";
        _weeklyReset.Header = $"Resets {FormatReset(s.Weekly.ResetsAt)}";

        var statusText = s.Status switch
        {
            UsageStatus.Offline => "Offline — last value may be stale",
            UsageStatus.RateLimited => "Rate limited by Claude API",
            UsageStatus.Unauthenticated => "Not signed in — open Settings to add a token",
            _ => "",
        };
        _statusLine.Header = statusText;
        _statusLine.Visibility = string.IsNullOrEmpty(statusText) ? Visibility.Collapsed : Visibility.Visible;
    }

    private void UpdateToolTip()
    {
        var s = _snapshot;
        if (s is null) { _tray.ToolTipText = "ClaudeBar"; return; }
        _tray.ToolTipText =
            $"ClaudeBar\nSession: {s.Session.Percent:F0}%\nWeekly: {s.Weekly.Percent:F0}%";
    }

    public static string FormatReset(DateTimeOffset? d)
    {
        if (d is null) return "—";
        var delta = d.Value - DateTimeOffset.UtcNow;
        if (delta.TotalMilliseconds <= 0) return "now";
        var mins = (int)Math.Round(delta.TotalMinutes);
        if (mins < 60) return $"in {mins} min";
        var hrs = mins / 60;
        var rem = mins % 60;
        if (hrs < 24) return rem > 0 ? $"in {hrs}h {rem}m" : $"in {hrs}h";
        var days = hrs / 24;
        var remH = hrs % 24;
        return remH > 0 ? $"in {days}d {remH}h" : $"in {days}d";
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
        try { _timer.Stop(); } catch { }
        SettingsStore.Instance.PropertyChanged -= OnSettingsChanged;
        try { _floatingMeter?.Close(); } catch { }
        _floatingMeter = null;
        _tray.Dispose();
    }
}
