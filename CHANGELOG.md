# Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.0.0 — 2026-04-22

Initial stable release. Spans _macOS_, _Windows_, and seven _Linux_ desktop environments (_GNOME_, _KDE_ Plasma, _Cinnamon_, _XFCE_, _MATE_, _Budgie_, _LXQt_), plus a shared _Rust_ helper binary for _OAuth_ and Secret Service token storage.

### Added

#### Linux (GNOME Shell extension)

- GNOME Shell top-bar indicator with two stacked bars.
- OAuth PKCE sign-in (loopback redirect); tokens stored via libsecret.
- Preferences: poll interval, color thresholds, percentage labels.
- Supports GNOME Shell 45 / 46 / 47 / 48.

#### Linux (other desktop environments)

- **KDE Plasma 6**: native Plasmoid (QML + JS) under `apps/linux/kde/`.
- **Cinnamon**: native applet (GJS) under `apps/linux/cinnamon/` — shares the same libsecret token storage as the GNOME extension.
- **XFCE**: native GTK3 panel plugin (C + libxfce4panel) under `apps/linux/xfce/`.
- **MATE**: Python panel applet under `apps/linux/mate/`.
- **Budgie**: Vala panel applet under `apps/linux/budgie/`.
- **LXQt**: C++/Qt5 panel plugin under `apps/linux/lxqt/`.
- **`claudebar-helper`** — shared Rust CLI under `apps/linux/common/claudebar-helper/` that all non-GNOME Linux front-ends delegate to: handles OAuth (PKCE + loopback) and token storage in the FreeDesktop Secret Service. Also provides a `tray` subcommand that runs as a cross-DE StatusNotifierItem fallback.
- **Arch Linux packaging**: PKGBUILDs under `packaging/arch/` for every front-end plus the helper — ready for AUR publication.

#### macOS

- `NSStatusItem` menu bar indicator with a custom-drawn two-bar indicator.
- OAuth PKCE sign-in; tokens stored in the macOS Keychain.
- SwiftUI preferences window (Account / Display / Advanced).
- Requires macOS 13 Ventura or later.

#### Windows

- .NET 8 WPF tray icon (via `H.NotifyIcon.Wpf`), dynamically rendered bars.
- Optional always-on-top floating desktop meter rendering full-size bars beside the tray. Draggable, lock-position, opacity slider, width control. Co-exists with the tray icon.
- OAuth PKCE sign-in; tokens encrypted at rest with DPAPI (user scope).
- WPF preferences window with Account / Display / Advanced tabs.
- Requires Windows 10 (1809) or later.

#### CI / release pipeline

- CI matrix builds and lints every platform on its native runner.
- Release workflow produces the Linux helper binary (x86_64), GNOME `.shell-extension.zip`, KDE `.plasmoid`, Cinnamon applet zip, macOS `.app` zip, and Windows x64 publish zip — all attached to GitHub releases on tagged pushes, with SHA256 checksums for verification.
