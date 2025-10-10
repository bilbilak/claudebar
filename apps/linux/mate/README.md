# claudebar — MATE panel applet

Python-based applet for the **MATE desktop**'s `mate-panel`. Uses `MatePanelApplet` GIR bindings + GTK3 + Cairo. Delegates data fetching, OAuth and token storage to [`claudebar-helper`](../common/claudebar-helper/).

## Dependencies

Build-time, on Ubuntu / Linux Mint / Debian:

```sh
sudo apt install python3-gi python3-gi-cairo gir1.2-matepanelapplet-4.0 gir1.2-gtk-3.0 gettext
```

Plus `claudebar-helper` from the repo root (`make install-helper` — needs the deps in [../common/claudebar-helper/README.md](../common/claudebar-helper/README.md), notably `libdbus-1-dev`).

Runtime:

- `mate-panel` ≥ 1.20
- `claudebar-helper` discoverable in one of: `$CLAUDEBAR_HELPER`, `$PATH`, `~/.local/bin`, `/usr/local/bin`, `/usr/bin`, `/usr/libexec`. The applet probes all six at startup, so the default `make install-helper` (which lands the binary in `~/.local/bin`) Just Works under DBus session activation.

## Install

```sh
sudo make install PREFIX=/usr
```

**`PREFIX=/usr` is required, not optional.** `mate-panel` only scans the compile-time-pinned `$prefix/share/mate-panel/applets/` directory baked at the time _your distro_ built `mate-panel`. On Ubuntu / Mint / Debian that's `/usr/share/mate-panel/applets/`; nothing under `XDG_DATA_DIRS` is consulted. The Makefile's `PREFIX=/usr/local` default lands files where the panel never looks, and the applet won't appear in **Add to Panel**.

Then restart `mate-panel` so it re-reads applet definitions and DBus picks up the new service file:

```sh
nohup mate-panel --replace >/dev/null 2>&1 & disown
```

Right-click the panel → **Add to Panel…** → **ClaudeBar**.

## Right-click menu

Refresh · Sign in with Claude… · Sign out · Open claude.ai/settings/usage · Preferences.

The Preferences entry opens a small dialog with poll interval, warn / critical thresholds, and an optional helper-path override. Settings persist to `~/.config/claudebar/mate.json`.

## Uninstall

```sh
sudo make uninstall PREFIX=/usr
```

If you previously installed without `PREFIX=/usr`, also run the equivalent with `PREFIX=/usr/local` to clean up that prefix.

## Notes

The [`packaging/arch/claudebar-mate/PKGBUILD`](../../../packaging/arch/) and the upcoming `.deb` produce the right layout automatically — `PREFIX=/usr` is the right answer for any system-wide install, and packagers bake it in.

## License

GPL-3.0-or-later.
