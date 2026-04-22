using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using ClaudeBar.Api;
using ClaudeBar.Settings;

namespace ClaudeBar.UI;

public partial class FloatingMeterWindow : Window
{
    public event EventHandler? RefreshRequested;
    public event EventHandler? PrefsRequested;
    public event EventHandler? HideRequested;

    public FloatingMeterWindow()
    {
        InitializeComponent();

        var s = SettingsStore.Instance;
        LockMenuItem.IsChecked = s.FloatingMeterLocked;
        ApplySettings(s);

        SourceInitialized += (_, _) => RestorePosition();
        Loaded += (_, _) => UpdateOpacity();
        LocationChanged += OnLocationChanged;
        s.PropertyChanged += OnSettingsChanged;
        Closed += (_, _) => s.PropertyChanged -= OnSettingsChanged;
    }

    public void SetSnapshot(UsageSnapshot? snapshot)
    {
        Bars.Snapshot = snapshot;
    }

    private void ApplySettings(SettingsStore s)
    {
        Bars.WarnThreshold = s.WarnThreshold;
        Bars.CriticalThreshold = s.CriticalThreshold;
        Bars.ShowPercentages = s.ShowPercentages;
        Width = Math.Max(120, Math.Min(320, s.FloatingMeterWidth));
    }

    private void UpdateOpacity()
    {
        // 0–100 → 0.4–1.0 range to avoid an invisible widget.
        var pct = Math.Max(40, Math.Min(100, SettingsStore.Instance.FloatingMeterOpacity));
        Opacity = pct / 100.0;
    }

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        ApplySettings(SettingsStore.Instance);
        UpdateOpacity();
        LockMenuItem.IsChecked = SettingsStore.Instance.FloatingMeterLocked;
    }

    private void RestorePosition()
    {
        var s = SettingsStore.Instance;
        if (double.IsFinite(s.FloatingMeterX) && double.IsFinite(s.FloatingMeterY)
            && s.FloatingMeterX > 0 && s.FloatingMeterY > 0)
        {
            Left = s.FloatingMeterX;
            Top = s.FloatingMeterY;
            EnsureOnScreen();
            return;
        }

        // First run: dock near the bottom-right, a bit above the taskbar.
        var wa = SystemParameters.WorkArea;
        Left = wa.Right - Width - 12;
        Top = wa.Bottom - Height - 12;
    }

    private void EnsureOnScreen()
    {
        var wa = SystemParameters.VirtualScreenWidth > 0
            ? new Rect(SystemParameters.VirtualScreenLeft,
                       SystemParameters.VirtualScreenTop,
                       SystemParameters.VirtualScreenWidth,
                       SystemParameters.VirtualScreenHeight)
            : SystemParameters.WorkArea;
        if (Left + Width < wa.Left + 20) Left = wa.Left + 20;
        if (Top + Height < wa.Top + 20) Top = wa.Top + 20;
        if (Left > wa.Right - 20) Left = wa.Right - Width - 20;
        if (Top > wa.Bottom - 20) Top = wa.Bottom - Height - 20;
    }

    private void OnLocationChanged(object? sender, EventArgs e)
    {
        if (!IsLoaded) return;
        var s = SettingsStore.Instance;
        s.FloatingMeterX = Left;
        s.FloatingMeterY = Top;
    }

    // -- Dragging -----------------------------------------------------------

    private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (SettingsStore.Instance.FloatingMeterLocked) return;
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            try { DragMove(); } catch { /* DragMove throws if not holding left btn */ }
        }
    }

    // -- Context menu -------------------------------------------------------

    private void LockMenuItem_Click(object sender, RoutedEventArgs e)
    {
        SettingsStore.Instance.FloatingMeterLocked = LockMenuItem.IsChecked;
    }

    private void RefreshMenuItem_Click(object sender, RoutedEventArgs e)
    {
        RefreshRequested?.Invoke(this, EventArgs.Empty);
    }

    private void PrefsMenuItem_Click(object sender, RoutedEventArgs e)
    {
        PrefsRequested?.Invoke(this, EventArgs.Empty);
    }

    private void HideMenuItem_Click(object sender, RoutedEventArgs e)
    {
        HideRequested?.Invoke(this, EventArgs.Empty);
    }
}
