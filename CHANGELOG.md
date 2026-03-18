# Changelog

All notable changes to this project will be documented in this file.

## 1.1.0 — 2026-03-18

### Added

- **_GNOME Shell_ 50 compatibility** — declared in `apps/linux/gnome/metadata.json`'s `shell-version` array. _GNOME_ 50 released March 2026 on the regular semi-annual cadence.
- **_Cinnamon_ 6.6 compatibility** — declared in `apps/linux/cinnamon/metadata.json`'s `cinnamon-version` array. _Cinnamon_ 6.6 ships with _Linux Mint_ 22.2.

## 1.0.0 — 2025-10-17

### Added

- **macOS menu bar indicator** — native Swift app showing usage bars, preferences window, and OAuth sign-in via the system Keychain.
- **Windows tray icon + floating desktop meter** — WPF app with system tray presence and an always-on-top desktop widget.
- **GNOME Shell extension** — panel indicator written in TypeScript, built with esbuild.
- **KDE Plasma 6 Plasmoid** — QML-based panel widget with configurable settings.
- **Cinnamon applet** — JavaScript applet for the Cinnamon panel.
- **XFCE panel plugin** — C plugin with configure and about dialogs.
- **MATE panel applet** — Python applet with preferences support.
- **Budgie desktop applet** — Vala plugin with configure menu integration.
- **LXQt panel plugin** — C++ plugin with Qt5 and Qt6 support.
- **Shared Rust helper** — `claudebar-helper` binary providing OAuth (PKCE + loopback), Claude API client, secret-service token storage, and SNI tray icon for non-GNOME Linux DEs.
- **Multi-size app icon set** — freedesktop-compliant icons at 16×16 through 512×512 for all Linux desktop environments.
- **Internationalization** — 19 languages supported across all platforms via a shared `i18n/strings.yaml` source and per-platform translation files.
- **CI/CD workflows** — automated validation on push/PR and release artifact building (DMG, MSI, `.plasmoid`, shell extension zip, tarballs).
- **Arch Linux PKGBUILDs** — packaging definitions for all components.
- **Documentation** — platform-specific READMEs, screenshot galleries, brand guidelines, wiki sub-repository.
