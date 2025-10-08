using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ClaudeBar.Api;
using ClaudeBar.Settings;
using Microsoft.Win32;

namespace ClaudeBar.UI;

public static class UsageIconRenderer
{
    private const int CanvasSize = 32;
    private const double BarWidth = 26;
    private const double BarHeight = 6;
    private const double BarGap = 4;

    // Track color is chosen at render time based on the system theme so the
    // empty / loading state has visible bars on both light and dark taskbars.
    // Light theme = dark track on light bg; dark theme = light track on dark bg.
    private static readonly Color TrackColorLight = Color.FromRgb(64, 64, 70);
    private static readonly Color TrackColorDark = Color.FromRgb(200, 200, 210);

    private static readonly Color OkColor = Color.FromRgb(66, 186, 96);
    private static readonly Color WarnColor = Color.FromRgb(245, 158, 63);
    private static readonly Color CritColor = Color.FromRgb(237, 68, 68);
    private static readonly Color MutedColor = Color.FromRgb(160, 160, 160);

    // H.NotifyIcon 2.0.131's pipeline is:
    //    BitmapImage(UriSource) → read URI bytes → new System.Drawing.Icon(stream, size)
    // System.Drawing.Icon's stream constructor only accepts ICO format, so we
    // write a real .ico file (Vista+ ICO format with PNG-encoded image data)
    // and point UriSource at it.
    private static readonly string IconCachePath = Path.Combine(
        Path.GetTempPath(), "claudebar-tray-icon.ico");

    public static ImageSource Render(UsageSnapshot? snapshot, SettingsStore settings)
    {
        var status = snapshot?.Status ?? UsageStatus.Offline;
        var sessionPct = snapshot?.Session.Percent ?? 0;
        var weeklyPct = snapshot?.Weekly.Percent ?? 0;
        var trackColor = IsSystemUsingLightTheme() ? TrackColorLight : TrackColorDark;

        var visual = new DrawingVisual();
        using (var ctx = visual.RenderOpen())
        {
            double x = (CanvasSize - BarWidth) / 2.0;
            double totalH = BarHeight * 2 + BarGap;
            double yTop = (CanvasSize - totalH) / 2.0;
            double yBot = yTop + BarHeight + BarGap;

            DrawBar(ctx, x, yTop, BarWidth, BarHeight, sessionPct, status,
                settings.WarnThreshold, settings.CriticalThreshold, trackColor);
            DrawBar(ctx, x, yBot, BarWidth, BarHeight, weeklyPct, status,
                settings.WarnThreshold, settings.CriticalThreshold, trackColor);
        }

        var bmp = new RenderTargetBitmap(CanvasSize, CanvasSize, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(visual);
        bmp.Freeze();

        // Encode to PNG, then wrap in an ICO container, and write to disk.
        // H.NotifyIcon hands the URI's raw bytes to System.Drawing.Icon's
        // stream constructor, which only accepts ICO format.
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bmp));
        using var pngMs = new MemoryStream();
        encoder.Save(pngMs);
        File.WriteAllBytes(IconCachePath, WrapPngAsIco(pngMs.ToArray(), CanvasSize, CanvasSize));

        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        // Skip BitmapImage's URI cache so subsequent renders see the new file
        // contents, not whatever was at this URI on the first load.
        image.CreateOptions = BitmapCreateOptions.IgnoreImageCache;
        image.UriSource = new Uri(IconCachePath);
        image.EndInit();
        image.Freeze();
        return image;
    }

    /// <summary>
    /// Wraps a PNG payload in a single-image ICO container. Vista+ supports
    /// PNG-encoded ICO entries; the layout is:
    ///   ICONDIR (6 bytes) + ICONDIRENTRY (16 bytes) + PNG bytes.
    /// All fields are little-endian. Width/height of 0 means "256".
    /// </summary>
    private static byte[] WrapPngAsIco(byte[] png, int width, int height)
    {
        using var ms = new MemoryStream(22 + png.Length);
        using var bw = new BinaryWriter(ms);

        // ICONDIR
        bw.Write((ushort)0);   // reserved (must be 0)
        bw.Write((ushort)1);   // type: 1 = icon
        bw.Write((ushort)1);   // image count

        // ICONDIRENTRY (one image)
        bw.Write((byte)(width >= 256 ? 0 : width));
        bw.Write((byte)(height >= 256 ? 0 : height));
        bw.Write((byte)0);     // color palette count (0 for no palette)
        bw.Write((byte)0);     // reserved
        bw.Write((ushort)1);   // color planes
        bw.Write((ushort)32);  // bits per pixel
        bw.Write((uint)png.Length);
        bw.Write((uint)22);    // offset to image data (after ICONDIR + ICONDIRENTRY)

        bw.Write(png);
        bw.Flush();
        return ms.ToArray();
    }

    private static void DrawBar(DrawingContext ctx,
        double x, double y, double w, double h,
        double percent, UsageStatus status, int warn, int crit,
        Color trackColor)
    {
        double r = h / 2.0;
        var trackBrush = new SolidColorBrush(trackColor);
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

    private static bool IsSystemUsingLightTheme()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return (key?.GetValue("SystemUsesLightTheme") as int?) == 1;
        }
        catch
        {
            return false;  // assume dark on registry read failure
        }
    }
}
