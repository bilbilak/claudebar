//! StatusNotifierItem tray mode — cross-DE fallback for DEs without a native applet.

use anyhow::Result;
use ksni::{menu::StandardItem, Icon, MenuItem, Tray};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::api::{self, Snapshot, Status};
use crate::auth;
use crate::icon;

struct ClaudebarTray {
    snapshot: Arc<Mutex<Option<Snapshot>>>,
    warn: u8,
    crit: u8,
}

impl Tray for ClaudebarTray {
    fn id(&self) -> String {
        "org.bilbilak.claudebar".into()
    }

    fn title(&self) -> String {
        "ClaudeBar".into()
    }

    fn tool_tip(&self) -> ksni::ToolTip {
        let s = self.snapshot.lock().ok().and_then(|s| s.clone());
        let (title, text) = match &s {
            None => ("ClaudeBar".into(), "Loading…".into()),
            Some(snap) => {
                let title = "ClaudeBar".to_string();
                let text = format!(
                    "Current session: {:.0}%\nWeekly (all models): {:.0}%",
                    snap.session.percent, snap.weekly.percent
                );
                (title, text)
            }
        };
        ksni::ToolTip {
            icon_name: String::new(),
            icon_pixmap: Vec::new(),
            title,
            description: text,
        }
    }

    fn icon_pixmap(&self) -> Vec<Icon> {
        let snap = self.snapshot.lock().ok().and_then(|s| s.clone());
        // Provide 22px (fits most panels) and 32px (for HiDPI) variants.
        let sizes = [22u32, 32];
        sizes
            .iter()
            .map(|&sz| {
                let pm = icon::render(sz, snap.as_ref(), self.warn, self.crit);
                Icon {
                    width: sz as i32,
                    height: sz as i32,
                    data: icon::to_argb32(&pm),
                }
            })
            .collect()
    }

    fn activate(&mut self, _x: i32, _y: i32) {
        // Left-click: refresh immediately on activation.
        let snap = api::fetch_snapshot();
        if let Ok(mut guard) = self.snapshot.lock() {
            *guard = Some(snap);
        }
    }

    fn menu(&self) -> Vec<MenuItem<Self>> {
        let snap = self.snapshot.lock().ok().and_then(|s| s.clone());
        let session = snap.as_ref().map(|s| s.session.percent).unwrap_or(0.0);
        let weekly = snap.as_ref().map(|s| s.weekly.percent).unwrap_or(0.0);
        let session_reset = format_reset(snap.as_ref().and_then(|s| s.session.resets_at));
        let weekly_reset = format_reset(snap.as_ref().and_then(|s| s.weekly.resets_at));
        let status_line = snap
            .as_ref()
            .map(|s| match s.status {
                Status::Ok => String::new(),
                Status::Offline => "Offline — last value may be stale".into(),
                Status::RateLimited => "Rate limited by Claude API".into(),
                Status::Unauthenticated => {
                    "Not signed in — run: claudebar-helper signin".into()
                }
            })
            .unwrap_or_default();

        let mut items: Vec<MenuItem<Self>> = Vec::new();
        items.push(
            StandardItem {
                label: format!("Current session: {:.0}%", session),
                enabled: false,
                ..Default::default()
            }
            .into(),
        );
        items.push(
            StandardItem {
                label: format!("  resets {}", session_reset),
                enabled: false,
                ..Default::default()
            }
            .into(),
        );
        items.push(
            StandardItem {
                label: format!("Weekly (all models): {:.0}%", weekly),
                enabled: false,
                ..Default::default()
            }
            .into(),
        );
        items.push(
            StandardItem {
                label: format!("  resets {}", weekly_reset),
                enabled: false,
                ..Default::default()
            }
            .into(),
        );
        if !status_line.is_empty() {
            items.push(
                StandardItem {
                    label: status_line,
                    enabled: false,
                    ..Default::default()
                }
                .into(),
            );
        }
        items.push(MenuItem::Separator);
        items.push(
            StandardItem {
                label: "Refresh now".into(),
                activate: Box::new(|tray: &mut Self| {
                    let snap = api::fetch_snapshot();
                    if let Ok(mut guard) = tray.snapshot.lock() {
                        *guard = Some(snap);
                    }
                }),
                ..Default::default()
            }
            .into(),
        );
        items.push(
            StandardItem {
                label: "Open claude.ai/settings/usage".into(),
                activate: Box::new(|_tray| {
                    let _ = webbrowser::open("https://claude.ai/settings/usage");
                }),
                ..Default::default()
            }
            .into(),
        );
        items.push(MenuItem::Separator);
        items.push(
            StandardItem {
                label: "Quit".into(),
                activate: Box::new(|_tray| std::process::exit(0)),
                ..Default::default()
            }
            .into(),
        );
        items
    }
}

pub fn run(interval_secs: u64) -> Result<()> {
    // Warm-load tokens so `is signed in` state is reflected before first poll.
    let _ = auth::load();

    let snapshot = Arc::new(Mutex::new(None));
    let tray = ClaudebarTray {
        snapshot: snapshot.clone(),
        warn: 60,
        crit: 85,
    };

    let service = ksni::TrayService::new(tray);
    let handle = service.handle();
    service.spawn();

    // Initial fetch
    {
        let snap = api::fetch_snapshot();
        if let Ok(mut g) = snapshot.lock() {
            *g = Some(snap);
        }
        handle.update(|_| {});
    }

    // Poll loop
    let snapshot_for_loop = snapshot.clone();
    let handle_for_loop = handle.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_secs(interval_secs));
        let snap = api::fetch_snapshot();
        if let Ok(mut g) = snapshot_for_loop.lock() {
            *g = Some(snap);
        }
        handle_for_loop.update(|_| {});
    });

    // Block forever on Ctrl-C or SIGTERM.
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    rt.block_on(async {
        let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("installing SIGTERM handler");
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {},
            _ = term.recv() => {},
        }
    });
    Ok(())
}

fn format_reset(dt: Option<chrono::DateTime<chrono::Utc>>) -> String {
    let Some(dt) = dt else { return "—".into() };
    let now = chrono::Utc::now();
    let delta = dt - now;
    if delta.num_milliseconds() <= 0 {
        return "now".into();
    }
    let mins = delta.num_minutes();
    if mins < 60 {
        return format!("in {mins} min");
    }
    let hrs = mins / 60;
    let rem = mins % 60;
    if hrs < 24 {
        if rem > 0 {
            return format!("in {hrs}h {rem}m");
        }
        return format!("in {hrs}h");
    }
    let days = hrs / 24;
    let rem_h = hrs % 24;
    if rem_h > 0 {
        format!("in {days}d {rem_h}h")
    } else {
        format!("in {days}d")
    }
}
