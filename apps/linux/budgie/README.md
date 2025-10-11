# claudebar — Budgie panel applet

Vala-based applet for the **Budgie desktop** (Ubuntu Budgie, Solus, Buddies of Budgie). Two bars drawn via GTK3 + Cairo. Delegates data fetching, OAuth and token storage to [`claudebar-helper`](../common/claudebar-helper/).

## Build requirements

- `budgie-1.0` (Budgie 10.6+) **or** `budgie-2.0` (Budgie 10.10+, Solus, recent Buddies of Budgie)
- `gtk+-3.0`, `json-glib-1.0`
- `libpeas-1.0` for Budgie 1.x **or** `libpeas-2` for Budgie 2.x (matches the chosen Budgie major)
- `valac`, `meson`, `ninja`, a C compiler

Debian/Ubuntu Budgie (Budgie 1.x): `sudo apt install budgie-core-dev libpeas-dev libjson-glib-dev libgtk-3-dev valac meson ninja-build`

Solus (Budgie 2.x): `sudo eopkg install -c system.devel meson ninja vala budgie-desktop-devel libpeas-2-devel libgtk-3-devel libjson-glib-devel`

Arch: `sudo pacman -S budgie-desktop libpeas json-glib gtk3 vala meson`

## Install

From the repo root:

```sh
sudo make install-budgie PREFIX=/usr
```

Or step by step from this directory:

```sh
meson setup build --buildtype=release --prefix=/usr
meson compile -C build
sudo meson install -C build
```

**`--prefix=/usr` is required, not optional.** `budgie-panel` only loads plugins from the compile-time-pinned `libdir/budgie-desktop/plugins/`. On Ubuntu Budgie that's `/usr/lib/x86_64-linux-gnu/budgie-desktop/plugins/`; nothing under `XDG_DATA_DIRS` is consulted. The meson default `--prefix=/usr/local` lands the plugin where the panel never looks.

Then add the applet via Budgie's settings tool:

- **Budgie 1.x**: right-click the Budgie panel → **Panel preferences** → **+** → **ClaudeBar**.
- **Budgie 2.x** (Solus, etc.): launch `budgie-desktop-settings`, pick the panel, click **+ Add applet**, and choose **ClaudeBar**. The right-click panel menu was removed in 10.10+.

Make sure `claudebar-helper` is also installed (see [`../common/claudebar-helper/`](../common/claudebar-helper/)). The applet probes `$CLAUDEBAR_HELPER`, `$PATH`, `~/.local/bin`, `/usr/local/bin`, `/usr/bin`, and `/usr/libexec` at startup, so the default `make install-helper` location works without further configuration.

## License

GPL-3.0-or-later.
