using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using ClaudeBar.Auth;
using ClaudeBar.Resources;
using ClaudeBar.Settings;

namespace ClaudeBar.UI;

public partial class PreferencesWindow : Window
{
    private OAuth.LoginFlow? _activeLogin;
    private string? _activeAuthorizeUri;
    private static readonly Regex DigitsOnly = new("^[0-9]+$", RegexOptions.Compiled);

    public PreferencesWindow()
    {
        InitializeComponent();

        var s = SettingsStore.Instance;
        ShowPercentagesCheck.IsChecked = s.ShowPercentages;
        WarnThresholdBox.Text = s.WarnThreshold.ToString();
        CriticalThresholdBox.Text = s.CriticalThreshold.ToString();
        PollIntervalBox.Text = s.PollInterval.ToString();
        FloatingMeterCheck.IsChecked = s.FloatingMeterEnabled;
        OpacitySlider.Value = s.FloatingMeterOpacity;
        OpacityLabel.Text = $"{s.FloatingMeterOpacity}%";
        MeterWidthBox.Text = s.FloatingMeterWidth.ToString();

        Loaded += async (_, _) => await RefreshStatusAsync();
        Closed += (_, _) => _activeLogin?.Cancel();
    }

    // -- Account tab ----------------------------------------------------------

    private async Task RefreshStatusAsync()
    {
        var tokens = await Task.Run(() => TokenStore.Load());
        if (tokens is null)
        {
            StatusText.Text = Strings.AuthNotSignedIn;
            SignInButton.Visibility = Visibility.Visible;
            SignOutButton.Visibility = Visibility.Collapsed;
        }
        else
        {
            var tail = tokens.AccessToken.Length >= 6
                ? tokens.AccessToken[^6..]
                : tokens.AccessToken;
            // AuthSignedInToken localizes "Signed in (token ends '…%s')".
            // Convert %s to .NET's {0} for string.Format.
            StatusText.Text = string.Format(
                Strings.AuthSignedInToken.Replace("%s", "{0}"),
                tail);
            SignInButton.Visibility = Visibility.Collapsed;
            SignOutButton.Visibility = Visibility.Visible;
        }
    }

    private async void SignInButton_Click(object sender, RoutedEventArgs e)
    {
        ErrorText.Visibility = Visibility.Collapsed;
        ErrorText.Text = "";

        try
        {
            var flow = OAuth.StartLogin();
            _activeLogin = flow;
            _activeAuthorizeUri = flow.AuthorizeUri;

            SetBusy(true);

            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = flow.AuthorizeUri,
                    UseShellExecute = true,
                });
            }
            catch
            {
                // If we can't open the browser, at least put the URL on the
                // clipboard so the user can paste it themselves. (The
                // CopyLinkButton, also visible while busy, does the same
                // thing on demand if the auto-open landed in the wrong
                // browser.)
                TrySetClipboard(flow.AuthorizeUri);
                ErrorText.Text = Strings.AuthCouldNotStart;
                ErrorText.Visibility = Visibility.Visible;
            }

            var tokens = await flow.AwaitResultAsync();
            TokenStore.Store(tokens);
            AuthEvents.RaiseChanged();
            await RefreshStatusAsync();
        }
        catch (OperationCanceledException)
        {
            // user cancelled
        }
        catch (Exception ex)
        {
            ErrorText.Text = ex.Message;
            ErrorText.Visibility = Visibility.Visible;
        }
        finally
        {
            _activeLogin = null;
            _activeAuthorizeUri = null;
            SetBusy(false);
        }
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        _activeLogin?.Cancel();
    }

    private void CopyLinkButton_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrEmpty(_activeAuthorizeUri))
        {
            TrySetClipboard(_activeAuthorizeUri);
        }
    }

    private static void TrySetClipboard(string text)
    {
        // Clipboard.SetText can occasionally throw COMException when another
        // process has the clipboard open. The URL is non-critical UX so just
        // swallow.
        try { Clipboard.SetText(text); }
        catch { /* best effort */ }
    }

    private async void SignOutButton_Click(object sender, RoutedEventArgs e)
    {
        TokenStore.Clear();
        AuthEvents.RaiseChanged();
        await RefreshStatusAsync();
    }

    private void SetBusy(bool busy)
    {
        SignInButton.IsEnabled = !busy;
        SignOutButton.IsEnabled = !busy;
        CancelButton.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        CopyLinkButton.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        BusyText.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
    }

    // -- Display tab ----------------------------------------------------------

    private void ShowPercentagesCheck_Changed(object sender, RoutedEventArgs e)
    {
        SettingsStore.Instance.ShowPercentages = ShowPercentagesCheck.IsChecked == true;
    }

    private void WarnThresholdBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (int.TryParse(WarnThresholdBox.Text, out var v))
        {
            SettingsStore.Instance.WarnThreshold = v;
        }
        WarnThresholdBox.Text = SettingsStore.Instance.WarnThreshold.ToString();
    }

    private void CriticalThresholdBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (int.TryParse(CriticalThresholdBox.Text, out var v))
        {
            SettingsStore.Instance.CriticalThreshold = v;
        }
        CriticalThresholdBox.Text = SettingsStore.Instance.CriticalThreshold.ToString();
    }

    // -- Floating meter -------------------------------------------------------

    private void FloatingMeterCheck_Changed(object sender, RoutedEventArgs e)
    {
        SettingsStore.Instance.FloatingMeterEnabled = FloatingMeterCheck.IsChecked == true;
    }

    private void OpacitySlider_ValueChanged(object sender,
        System.Windows.RoutedPropertyChangedEventArgs<double> e)
    {
        var v = (int)Math.Round(e.NewValue);
        SettingsStore.Instance.FloatingMeterOpacity = v;
        if (OpacityLabel is not null)
            OpacityLabel.Text = $"{SettingsStore.Instance.FloatingMeterOpacity}%";
    }

    private void MeterWidthBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (int.TryParse(MeterWidthBox.Text, out var v))
        {
            SettingsStore.Instance.FloatingMeterWidth = v;
        }
        MeterWidthBox.Text = SettingsStore.Instance.FloatingMeterWidth.ToString();
    }

    // -- Advanced tab ---------------------------------------------------------

    private void PollIntervalBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (int.TryParse(PollIntervalBox.Text, out var v))
        {
            SettingsStore.Instance.PollInterval = v;
        }
        PollIntervalBox.Text = SettingsStore.Instance.PollInterval.ToString();
    }

    // -- Shared ---------------------------------------------------------------

    private void NumericInput_Preview(object sender, TextCompositionEventArgs e)
    {
        e.Handled = !DigitsOnly.IsMatch(e.Text);
    }
}
