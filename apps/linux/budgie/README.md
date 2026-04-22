# claudebar — Budgie panel applet

Vala-based applet for the **Budgie desktop** (Ubuntu Budgie, Solus, Buddies of Budgie). Two bars drawn via GTK3 + Cairo. Delegates data fetching, OAuth and token storage to [`claudebar-helper`](../common/claudebar-helper/).

## Build requirements

- `budgie-1.0` (≥ 2.0 — Budgie 10.6+ / Budgie Desktop View)
- `gtk+-3.0`, `libpeas-1.0`, `json-glib-1.0`
- `valac`, `meson`, `ninja`, a C compiler

Debian/Ubuntu Budgie: `sudo apt install budgie-core-dev libpeas-dev libjson-glib-dev libgtk-3-dev valac meson ninja-build`

Arch: `sudo pacman -S budgie-desktop libpeas json-glib gtk3 vala meson`

## Install

```sh
meson setup build --buildtype=release
meson compile -C build
sudo meson install -C build
```

Then right-click the Budgie panel → **Panel preferences** → **+** → **ClaudeBar**.

Make sure `claudebar-helper` is also installed.

## License

GPL-3.0-or-later.
