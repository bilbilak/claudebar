using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using ClaudeBar.Api;
using ClaudeBar.Auth;
using ClaudeBar.Resources;
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

    private readonly MenuItem _sessionItem = new() { Header = Strings.StatSessionDash, IsEnabled = false, StaysOpenOnClick = true };
    private readonly MenuItem _sessionReset = new() { Header = "", IsEnabled = false, StaysOpenOnClick = true };
    private readonly MenuItem _weeklyItem = new() { Header = Strings.StatWeeklyDash, IsEnabled = false, StaysOpenOnClick = true };
    private readonly MenuItem _weeklyReset = new() { Header = "", IsEnabled = false, StaysOpenOnClick = true };
    private readonly MenuItem _statusLine = new() { Header = "", IsEnabled = false, Visibility = Visibility.Collapsed, StaysOpenOnClick = true };

    public TrayIconManager()
    {
        _tray = new TaskbarIcon
        {
            ToolTipText = Strings.TooltipDefault,
            NoLeftClickDelay = true,
        };
        BuildMenu();
        UpdateIcon();
        // TaskbarIcon is a FrameworkElement that defers Shell_NotifyIcon
        // registration until WPF loads it into a visual tree. We create it
        // programmatically with no parent, so OnLoaded never fires and the
        // icon is never actually added to the system tray. ForceCreate()
        // bypasses the deferred-init path and registers immediately.
        _tray.ForceCreate();

        _timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(Math.Max(120, SettingsStore.Instance.PollInterval)),
        };
        _timer.Tick += (_, _) => _ = RefreshAsync();
        _timer.Start();

        SettingsStore.Instance.PropertyChanged += OnSettingsChanged;
        AuthEvents.Changed += OnAuthChanged;

        SyncFloatingMeter();
        _ = RefreshAsync();
    }

    private void OnAuthChanged(object? sender, EventArgs e)
    {
        // Sign-in/out can complete on any thread (the OAuth loopback runs on
        // a thread-pool task). Marshal onto the UI thread before touching tray
        // state from RefreshAsync.
        var dispatcher = _tray.Dispatcher;
        if (dispatcher.CheckAccess()) _ = RefreshAsync();
        else dispatcher.BeginInvoke(() => _ = RefreshAsync());
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
            Header = Strings.BrandName,
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

        var refresh = new MenuItem { Header = Strings.MenuRefreshNow };
        refresh.Click += (_, _) => _ = RefreshAsync();
        menu.Items.Add(refresh);

        var open = new MenuItem { Header = Strings.MenuOpenUsagePage };
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

        var prefs = new MenuItem { Header = Strings.MenuSettings };
        prefs.Click += (_, _) => ShowPreferences();
        menu.Items.Add(prefs);

        menu.Items.Add(new Separator());
        var quit = new MenuItem { Header = Strings.MenuQuit };
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
        _timer.Interval = TimeSpan.FromSeconds(Math.Max(120, SettingsStore.Instance.PollInterval));
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
        _sessionItem.Header = PrintfFormat(Strings.StatSessionWithPct, (int)Math.Round(s.Session.Percent));
        _sessionReset.Header = PrintfFormat(Strings.StatResets, FormatReset(s.Session.ResetsAt));
        _weeklyItem.Header = PrintfFormat(Strings.StatWeeklyWithPct, (int)Math.Round(s.Weekly.Percent));
        _weeklyReset.Header = PrintfFormat(Strings.StatResets, FormatReset(s.Weekly.ResetsAt));

        var statusText = s.Status switch
        {
            UsageStatus.Offline => Strings.StatusOffline,
            UsageStatus.RateLimited => Strings.StatusRateLimited,
            UsageStatus.Unauthenticated => Strings.StatusUnauthenticated,
            _ => "",
        };
        _statusLine.Header = statusText;
        _statusLine.Visibility = string.IsNullOrEmpty(statusText) ? Visibility.Collapsed : Visibility.Visible;
    }

    private void UpdateToolTip()
    {
        var s = _snapshot;
        if (s is null) { _tray.ToolTipText = Strings.TooltipDefault; return; }
        _tray.ToolTipText = PrintfFormat(
            Strings.TooltipLines,
            (int)Math.Round(s.Session.Percent),
            (int)Math.Round(s.Weekly.Percent));
    }

    public static string FormatReset(DateTimeOffset? d)
    {
        if (d is null) return Strings.TimeDash;
        var delta = d.Value - DateTimeOffset.UtcNow;
        if (delta.TotalMilliseconds <= 0) return Strings.TimeNow;
        var mins = (int)Math.Round(delta.TotalMinutes);
        if (mins < 60) return PrintfFormat(Strings.TimeInMinutes, mins);
        var hrs = mins / 60;
        var rem = mins % 60;
        if (hrs < 24)
        {
            return rem > 0
                ? PrintfFormat(Strings.TimeInHoursMinutes, hrs, rem)
                : PrintfFormat(Strings.TimeInHours, hrs);
        }
        var days = hrs / 24;
        var remH = hrs % 24;
        return remH > 0
            ? PrintfFormat(Strings.TimeInDaysHours, days, remH)
            : PrintfFormat(Strings.TimeInDays, days);
    }

    /// <summary>
    /// Tiny printf-style formatter for the subset of placeholders our YAML
    /// uses: %s (string), %d (integer), %% (literal percent). Arguments are
    /// substituted positionally into the template's %s/%d occurrences in
    /// left-to-right order. %% renders as a literal '%' in the output.
    ///
    /// We do this rather than convert the resource strings to .NET's {0}
    /// syntax up-front so the .resx values stay byte-identical to what the
    /// Python regen script writes from i18n/strings.yaml.
    /// </summary>
    private static string PrintfFormat(string template, params object[] args)
    {
        // Sentinel for shielding %% during the scan. Made deliberately
        // unlikely-in-real-text so it can't collide with user content.
        const string PctSentinel = "PCT";

        var ci = CultureInfo.CurrentUICulture;
        var shielded = template.Replace("%%", PctSentinel);

        var sb = new System.Text.StringBuilder(shielded.Length + 16);
        int i = 0, ai = 0;
        while (i < shielded.Length)
        {
            var c = shielded[i];
            if (c == '%' && i + 1 < shielded.Length)
            {
                var spec = shielded[i + 1];
                if (spec == 's' || spec == 'd')
                {
                    if (ai < args.Length)
                    {
                        var v = args[ai++];
                        sb.Append(spec == 'd' && v is IFormattable f
                            ? f.ToString(null, ci)
                            : v?.ToString() ?? "");
                    }
                    i += 2;
                    continue;
                }
            }
            sb.Append(c);
            i++;
        }

        return sb.Replace(PctSentinel, "%").ToString();
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
        try { _timer.Stop(); } catch { }
        SettingsStore.Instance.PropertyChanged -= OnSettingsChanged;
        AuthEvents.Changed -= OnAuthChanged;
        try { _floatingMeter?.Close(); } catch { }
        _floatingMeter = null;
        _tray.Dispose();
    }
}
