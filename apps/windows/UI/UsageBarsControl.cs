using System.Windows;
using System.Windows.Media;
using ClaudeBar.Api;

namespace ClaudeBar.UI;

/// <summary>
/// WPF control that paints the two usage bars (session + weekly). Used by the
/// floating desktop meter; the tray icon uses <see cref="UsageIconRenderer"/>
/// to produce a smaller bitmap representation of the same design.
/// </summary>
public sealed class UsageBarsControl : FrameworkElement
{
    public static readonly DependencyProperty SnapshotProperty = DependencyProperty.Register(
        nameof(Snapshot), typeof(UsageSnapshot), typeof(UsageBarsControl),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty WarnThresholdProperty = DependencyProperty.Register(
        nameof(WarnThreshold), typeof(int), typeof(UsageBarsControl),
        new FrameworkPropertyMetadata(60, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty CriticalThresholdProperty = DependencyProperty.Register(
        nameof(CriticalThreshold), typeof(int), typeof(UsageBarsControl),
        new FrameworkPropertyMetadata(85, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ShowPercentagesProperty = DependencyProperty.Register(
        nameof(ShowPercentages), typeof(bool), typeof(UsageBarsControl),
        new FrameworkPropertyMetadata(true, FrameworkPropertyMetadataOptions.AffectsRender));

    public UsageSnapshot? Snapshot
    {
        get => (UsageSnapshot?)GetValue(SnapshotProperty);
        set => SetValue(SnapshotProperty, value);
    }

    public int WarnThreshold
    {
        get => (int)GetValue(WarnThresholdProperty);
        set => SetValue(WarnThresholdProperty, value);
    }

    public int CriticalThreshold
    {
        get => (int)GetValue(CriticalThresholdProperty);
        set => SetValue(CriticalThresholdProperty, value);
    }

    public bool ShowPercentages
    {
        get => (bool)GetValue(ShowPercentagesProperty);
        set => SetValue(ShowPercentagesProperty, value);
    }

    private static readonly Color TrackColor = Color.FromArgb(80, 255, 255, 255);
    private static readonly Color OkColor = Color.FromRgb(66, 186, 96);
    private static readonly Color WarnColor = Color.FromRgb(245, 158, 63);
    private static readonly Color CritColor = Color.FromRgb(237, 68, 68);
    private static readonly Color MutedColor = Color.FromRgb(160, 160, 160);

    protected override void OnRender(DrawingContext ctx)
    {
        var w = ActualWidth;
        var h = ActualHeight;
        if (w <= 0 || h <= 0) return;

        var status = Snapshot?.Status ?? UsageStatus.Offline;
        var session = Snapshot?.Session.Percent ?? 0;
        var weekly = Snapshot?.Weekly.Percent ?? 0;

        double padding = 6;
        double labelWidth = ShowPercentages ? 36 : 0;
        double labelGap = ShowPercentages ? 4 : 0;
        double barsWidth = Math.Max(24, w - padding * 2 - labelWidth - labelGap);
        double barHeight = 8;
        double barGap = 4;
        double totalBarHeight = barHeight * 2 + barGap;
        double barsY = (h - totalBarHeight) / 2;
        double barsX = padding;

        DrawBar(ctx, barsX, barsY, barsWidth, barHeight, session, status);
        DrawBar(ctx, barsX, barsY + barHeight + barGap, barsWidth, barHeight, weekly, status);

        if (ShowPercentages)
        {
            var textColor = new SolidColorBrush(Color.FromArgb(240, 255, 255, 255));
            textColor.Freeze();
            var typeface = new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal,
                FontWeights.SemiBold, FontStretches.Normal);
            var labelX = barsX + barsWidth + labelGap;
            DrawLabel(ctx, $"{session:F0}%", textColor, typeface,
                labelX, barsY, labelWidth, barHeight);
            DrawLabel(ctx, $"{weekly:F0}%", textColor, typeface,
                labelX, barsY + barHeight + barGap, labelWidth, barHeight);
        }
    }

    private void DrawBar(DrawingContext ctx,
        double x, double y, double w, double h, double percent, UsageStatus status)
    {
        var r = h / 2.0;
        var track = new SolidColorBrush(TrackColor);
        track.Freeze();
        ctx.DrawRoundedRectangle(track, null, new Rect(x, y, w, h), r, r);

        var p = Math.Clamp(percent, 0, 100);
        if (p <= 0) return;

        var fw = Math.Max(h, w * p / 100.0);
        var color = ColorFor(p, status);
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        ctx.DrawRoundedRectangle(brush, null, new Rect(x, y, fw, h), r, r);
    }

    private static void DrawLabel(DrawingContext ctx, string text, Brush brush,
        Typeface typeface, double x, double y, double w, double h)
    {
        var ft = new FormattedText(
            text,
            System.Globalization.CultureInfo.InvariantCulture,
            FlowDirection.LeftToRight,
            typeface,
            10,
            brush,
            1.0)
        {
            TextAlignment = TextAlignment.Right,
            MaxTextWidth = w,
        };
        var textY = y + (h - ft.Height) / 2;
        ctx.DrawText(ft, new Point(x, textY));
    }

    private Color ColorFor(double percent, UsageStatus status)
    {
        if (status != UsageStatus.Ok) return MutedColor;
        if (percent >= CriticalThreshold) return CritColor;
        if (percent >= WarnThreshold) return WarnColor;
        return OkColor;
    }
}
