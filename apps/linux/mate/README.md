# claudebar — MATE panel applet

Python-based applet for the **MATE desktop**'s `mate-panel`. Uses `MatePanelApplet` GIR bindings + GTK3 + Cairo. Delegates data fetching, OAuth and token storage to [`claudebar-helper`](../common/claudebar-helper/).

## Dependencies

Runtime:

- `mate-panel` ≥ 1.20
- `python3-gi`, `python3-gi-cairo`, `gir1.2-matepanelapplet-4.0`, `gir1.2-gtk-3.0`
- `claudebar-helper` in `$PATH` (or set `CLAUDEBAR_HELPER=/path/to/helper` in the applet's environment)

## Install

```sh
sudo make install PREFIX=/usr      # system-wide
# or
make install PREFIX=$HOME/.local   # per-user (needs extra XDG_DATA_DIRS tweaks)
```

Then restart `mate-panel` (`mate-panel --replace &`) and right-click the panel → **Add to Panel…** → **ClaudeBar**.

## Right-click menu

Refresh · Sign in with Claude… · Sign out · Open claude.ai/settings/usage.

## Notes

MATE's per-user applet installation is finicky; system-wide install with `sudo` is the path of least resistance. The [`packaging/arch/claudebar-mate/PKGBUILD`](../../../packaging/arch/) and upcoming `.deb` produce the right layout automatically.

## License

GPL-3.0-or-later.
