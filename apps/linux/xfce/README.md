# claudebar — XFCE panel plugin

Native GTK3 plugin for **xfce4-panel** (≥ 4.14). Two bars drawn in the panel via Cairo. Delegates OAuth and token storage to [`claudebar-helper`](../common/claudebar-helper/).

## Build requirements

- `gtk+-3.0`, `libxfce4panel-2.0`, `libxfce4util-1.0`, `libxfce4ui-2`, `json-glib-1.0`
- `meson`, `ninja`, a C11 compiler

Debian/Ubuntu: `sudo apt install xfce4-dev-tools libxfce4panel-2.0-dev libxfce4util-dev libxfce4ui-2-dev libjson-glib-dev libgtk-3-dev meson`

Arch: `sudo pacman -S xfce4-panel libxfce4util libxfce4ui json-glib gtk3 meson`

## Install

```sh
meson setup build --buildtype=release
meson compile -C build
sudo meson install -C build
```

Then add the "ClaudeBar" item to your panel via the XFCE panel preferences.

Make sure `claudebar-helper` is also installed (see [`../common/claudebar-helper/`](../common/claudebar-helper/)).

## Right-click menu

Refresh · Sign in · Sign out · Open claude.ai/settings/usage.

## License

GPL-3.0-or-later.
