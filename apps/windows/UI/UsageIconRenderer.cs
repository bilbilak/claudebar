using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ClaudeBar.Api;
using ClaudeBar.Settings;

namespace ClaudeBar.UI;

public static class UsageIconRenderer
{
    private const int CanvasSize = 32;
    private const double BarWidth = 26;
    private const double BarHeight = 6;
    private const double BarGap = 4;

    private static readonly Color TrackColor = Color.FromArgb(120, 255, 255, 255);
    private static readonly Color OkColor = Color.FromRgb(66, 186, 96);
    private static readonly Color WarnColor = Color.FromRgb(245, 158, 63);
    private static readonly Color CritColor = Color.FromRgb(237, 68, 68);
    private static readonly Color MutedColor = Color.FromRgb(160, 160, 160);

    public static ImageSource Render(UsageSnapshot? snapshot, SettingsStore settings)
    {
        var status = snapshot?.Status ?? UsageStatus.Offline;
        var sessionPct = snapshot?.Session.Percent ?? 0;
        var weeklyPct = snapshot?.Weekly.Percent ?? 0;

        var visual = new DrawingVisual();
        using (var ctx = visual.RenderOpen())
        {
            double x = (CanvasSize - BarWidth) / 2.0;
            double totalH = BarHeight * 2 + BarGap;
            double yTop = (CanvasSize - totalH) / 2.0;
            double yBot = yTop + BarHeight + BarGap;

            DrawBar(ctx, x, yTop, BarWidth, BarHeight, sessionPct, status,
                settings.WarnThreshold, settings.CriticalThreshold);
            DrawBar(ctx, x, yBot, BarWidth, BarHeight, weeklyPct, status,
                settings.WarnThreshold, settings.CriticalThreshold);
        }

        var bmp = new RenderTargetBitmap(CanvasSize, CanvasSize, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(visual);
        bmp.Freeze();
        return bmp;
    }

    private static void DrawBar(DrawingContext ctx,
        double x, double y, double w, double h,
        double percent, UsageStatus status, int warn, int crit)
    {
        double r = h / 2.0;
        var trackBrush = new SolidColorBrush(TrackColor);
        trackBrush.Freeze();
        ctx.DrawRoundedRectangle(trackBrush, null, new Rect(x, y, w, h), r, r);

        var p = Math.Clamp(percent, 0, 100);
        if (p <= 0) return;

        var fw = Math.Max(h, w * p / 100.0);
        var fillColor = ColorFor(p, status, warn, crit);
        var fillBrush = new SolidColorBrush(fillColor);
        fillBrush.Freeze();
        ctx.DrawRoundedRectangle(fillBrush, null, new Rect(x, y, fw, h), r, r);
    }

    private static Color ColorFor(double percent, UsageStatus status, int warn, int crit)
    {
        if (status != UsageStatus.Ok) return MutedColor;
        if (percent >= crit) return CritColor;
        if (percent >= warn) return WarnColor;
        return OkColor;
    }
}
