//! Render the two-bar usage indicator into ARGB32 pixels for SNI tray icons.

use tiny_skia::{Color, Paint, PathBuilder, Pixmap, Rect, Transform};

use crate::api::{Snapshot, Status};

/// Produce an ARGB pixmap at the requested square size.
/// The bars occupy most of the icon; status colors match the GNOME extension.
pub fn render(size: u32, snapshot: Option<&Snapshot>, warn_pct: u8, crit_pct: u8) -> Pixmap {
    let mut pixmap = Pixmap::new(size, size).expect("failed to allocate pixmap");
    pixmap.fill(Color::from_rgba8(0, 0, 0, 0));

    let w = size as f32;
    let h = size as f32;

    let bar_width = (w * 0.78).round();
    let bar_height = (h * 0.18).round().max(3.0);
    let gap = (h * 0.12).round().max(2.0);
    let total_bars_h = bar_height * 2.0 + gap;
    let x = (w - bar_width) / 2.0;
    let y_top = (h - total_bars_h) / 2.0;
    let y_bot = y_top + bar_height + gap;

    let (status, session, weekly) = match snapshot {
        Some(s) => (s.status.clone(), s.session.percent, s.weekly.percent),
        None => (Status::Offline, 0.0, 0.0),
    };

    draw_bar(&mut pixmap, x, y_top, bar_width, bar_height, session, &status, warn_pct, crit_pct);
    draw_bar(&mut pixmap, x, y_bot, bar_width, bar_height, weekly, &status, warn_pct, crit_pct);
    pixmap
}

fn draw_bar(
    pm: &mut Pixmap,
    x: f32, y: f32, w: f32, h: f32,
    percent: f64, status: &Status,
    warn_pct: u8, crit_pct: u8,
) {
    let radius = h / 2.0;

    // Track
    {
        let track = build_rounded_rect(x, y, w, h, radius);
        let mut paint = Paint::default();
        paint.set_color(Color::from_rgba8(255, 255, 255, 64));
        paint.anti_alias = true;
        pm.fill_path(&track, &paint, tiny_skia::FillRule::Winding, Transform::identity(), None);
    }

    let p = percent.clamp(0.0, 100.0) as f32;
    if p <= 0.0 {
        return;
    }
    let fw = (w * p / 100.0).max(h);
    let color = color_for(p, status, warn_pct, crit_pct);
    let fill = build_rounded_rect(x, y, fw, h, radius);
    let mut paint = Paint::default();
    paint.set_color(color);
    paint.anti_alias = true;
    pm.fill_path(&fill, &paint, tiny_skia::FillRule::Winding, Transform::identity(), None);
}

fn build_rounded_rect(x: f32, y: f32, w: f32, h: f32, r: f32) -> tiny_skia::Path {
    let r = r.min(w / 2.0).min(h / 2.0);
    // Fallback to a plain rect path when radius is too small to matter.
    if r <= 0.5 {
        let mut pb = PathBuilder::new();
        pb.push_rect(Rect::from_xywh(x, y, w, h).expect("rect"));
        return pb.finish().expect("rect path");
    }
    let mut pb = PathBuilder::new();
    pb.move_to(x + r, y);
    pb.line_to(x + w - r, y);
    pb.quad_to(x + w, y, x + w, y + r);
    pb.line_to(x + w, y + h - r);
    pb.quad_to(x + w, y + h, x + w - r, y + h);
    pb.line_to(x + r, y + h);
    pb.quad_to(x, y + h, x, y + h - r);
    pb.line_to(x, y + r);
    pb.quad_to(x, y, x + r, y);
    pb.close();
    pb.finish().expect("rounded rect path")
}

fn color_for(percent: f32, status: &Status, warn: u8, crit: u8) -> Color {
    if !matches!(status, Status::Ok) {
        return Color::from_rgba8(160, 160, 160, 255);
    }
    if percent >= crit as f32 {
        return Color::from_rgba8(237, 68, 68, 255);
    }
    if percent >= warn as f32 {
        return Color::from_rgba8(245, 158, 63, 255);
    }
    Color::from_rgba8(66, 186, 96, 255)
}

/// Convert tiny-skia's RGBA byte order into ksni's expected ARGB (big-endian layout).
pub fn to_argb32(pixmap: &Pixmap) -> Vec<u8> {
    let src = pixmap.data();
    let mut out = Vec::with_capacity(src.len());
    for chunk in src.chunks_exact(4) {
        // tiny_skia stores RGBA premultiplied; SNI wants ARGB byte order in network byte order.
        let r = chunk[0];
        let g = chunk[1];
        let b = chunk[2];
        let a = chunk[3];
        out.extend_from_slice(&[a, r, g, b]);
    }
    out
}
