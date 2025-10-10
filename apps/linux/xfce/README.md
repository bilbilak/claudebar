# claudebar — XFCE panel plugin

Native GTK3 plugin for **xfce4-panel** (≥ 4.14). Two bars drawn in the panel via Cairo. Delegates OAuth and token storage to [`claudebar-helper`](../common/claudebar-helper/).

## Build requirements

- `gtk+-3.0`, `libxfce4panel-2.0`, `libxfce4util-1.0`, `libxfce4ui-2`, `json-glib-1.0`
- `meson`, `ninja`, a C11 compiler

Debian/Ubuntu: `sudo apt install xfce4-dev-tools libxfce4panel-2.0-dev libxfce4util-dev libxfce4ui-2-dev libjson-glib-dev libgtk-3-dev meson`

Arch: `sudo pacman -S xfce4-panel libxfce4util libxfce4ui json-glib gtk3 meson`

## Install

From the repo root, the top-level convenience target:

```sh
sudo make install-xfce PREFIX=/usr
```

Or step by step from this directory:

```sh
make i18n                                      # regenerate po/*.po from i18n/strings.yaml
meson setup build --buildtype=release --prefix=/usr
meson compile -C build
sudo meson install -C build
```

**`--prefix=/usr` is required, not optional.** `xfce4-panel` only scans the compile-time-pinned plugin directory baked at the time _your distro_ built the panel (`pkg-config --variable=plugindir libxfce4panel-2.0`). On Ubuntu / Mint / Debian that's `/usr/lib/x86_64-linux-gnu/xfce4/panel/plugins/`; nothing under `XDG_DATA_DIRS` is consulted. The meson default `--prefix=/usr/local` lands the plugin where the panel never looks.

The `make i18n` step is only required when the canonical translation source
at `i18n/strings.yaml` has changed; the generated `po/*.po` and `po/*.pot`
files are checked into the repo. On NixOS without `python3` on PATH, the
target falls back to `nix-shell -p 'python3.withPackages (ps: [ps.pyyaml])'`.

Then add the **ClaudeBar** item to your panel via the XFCE panel preferences.

Make sure `claudebar-helper` is also installed (see [`../common/claudebar-helper/`](../common/claudebar-helper/)). The plugin probes `$CLAUDEBAR_HELPER`, `$PATH`, `~/.local/bin`, `/usr/local/bin`, `/usr/bin`, and `/usr/libexec` at startup, so the default `make install-helper` location works without further configuration.

## Translations

User-visible strings in `src/claudebar.c` are marked with `_()` (gettext).
The runtime message domain is **`claudebar`** — the same domain used by the
other Linux panel plugins. The canonical English source is at
[`i18n/strings.yaml`](../../../i18n/strings.yaml); per-language `.po` files
in `po/` are regenerated from it by
[`scripts/regenerate-translations.py`](../../../scripts/regenerate-translations.py).

Meson compiles each `po/<lang>.po` into a `.mo` via its built-in `i18n`
module and installs them to
`${prefix}/share/locale/<lang>/LC_MESSAGES/claudebar.mo`.

## Right-click menu

Refresh · Sign in · Sign out · Open claude.ai/settings/usage.

## License

GPL-3.0-or-later.
