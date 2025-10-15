# Arch Linux (AUR) packaging

Each `PKGBUILD/` subdirectory corresponds to one AUR package. The intent is one AUR package per front-end, plus `claudebar-helper` as a shared dependency of the non-GNOME front-ends.

| Package                  | Provides                                       | Depends on                     |
| ------------------------ | ---------------------------------------------- | ------------------------------ |
| `claudebar-helper`       | `/usr/bin/claudebar-helper` (Rust CLI)         | `libsecret`, `dbus`            |
| `claudebar-gnome`        | GNOME Shell extension                          | `gnome-shell`, `libsecret`     |
| `claudebar-kde`          | KDE Plasma 6 widget                            | `plasma-workspace`, `claudebar-helper` |
| `claudebar-cinnamon`     | Cinnamon applet                                | `cinnamon`, `libsecret`        |
| `claudebar-xfce`         | XFCE panel plugin                              | `xfce4-panel`, `json-glib`, `claudebar-helper` |
| `claudebar-mate`         | MATE panel applet (Python)                     | `mate-panel`, `python-gobject`, `claudebar-helper` |
| `claudebar-budgie`       | Budgie panel applet                            | `budgie-desktop`, `json-glib`, `claudebar-helper` |
| `claudebar-lxqt`         | LXQt panel plugin                              | `lxqt-panel`, `claudebar-helper` |

## Publishing to the AUR

Each subdir is meant to be published as a separate AUR package. For each one:

```sh
# First time:
git clone ssh://aur@aur.archlinux.org/claudebar-helper.git aur-claudebar-helper
cp packaging/arch/claudebar-helper/PKGBUILD aur-claudebar-helper/
cd aur-claudebar-helper
makepkg --printsrcinfo > .SRCINFO
git add PKGBUILD .SRCINFO
git commit -sS -m "Initial upload: claudebar-helper 0.1.0"
git push

# Subsequent release:
cd aur-claudebar-helper
# edit pkgver= in PKGBUILD
updpkgsums                     # updates sha256sums
makepkg --printsrcinfo > .SRCINFO
git add PKGBUILD .SRCINFO
git commit -sS -m "Update to 0.1.1"
git push
```

## Local test

```sh
cd packaging/arch/claudebar-helper
makepkg -si             # build & install into the system
# or, without installing:
makepkg -sr
```

## Checksums

The `source=` line currently uses `SKIP` for checksums — this is fine for local development but must be replaced with real `sha256sums` before AUR publication. Run `updpkgsums` after bumping `pkgver`.

## License

GPL-3.0-or-later.
