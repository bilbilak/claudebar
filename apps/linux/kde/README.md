# claudebar — KDE Plasmoid

KDE Plasma 6 widget that shows your Claude.ai Max-plan session and weekly usage as two bars in the panel.

## Requirements

- **KDE Plasma 6.0+**
- **claudebar-helper** in `$PATH` (see [`apps/linux/common/claudebar-helper/`](../common/claudebar-helper/))
- A FreeDesktop Secret Service provider (KWallet is installed by default on KDE)

## Install

### From a release `.plasmoid` (end users)

Download `claudebar-helper-vX.Y.Z-linux-x64.tar.gz` and `claudebar-kde-vX.Y.Z.plasmoid` from the [release](https://github.com/bilbilak/claudebar/releases) page, then:

```sh
# Helper binary
mkdir -p ~/.local/bin
tar -xzf claudebar-helper-vX.Y.Z-linux-x64.tar.gz -C ~/.local/bin
chmod +x ~/.local/bin/claudebar-helper

# Plasmoid
kpackagetool6 --type=Plasma/Applet --install claudebar-kde-vX.Y.Z.plasmoid

# About-dialog and panel icon — KPackage doesn't auto-register icons
# bundled inside the package, so we copy ours into the user's XDG icon
# theme so KIconLoader can find it.
mkdir -p ~/.local/share/icons/hicolor/256x256/apps/
cp ~/.local/share/plasma/plasmoids/org.bilbilak.claudebar/contents/icons/claudebar.png \
   ~/.local/share/icons/hicolor/256x256/apps/claudebar.png
gtk-update-icon-cache -f ~/.local/share/icons/hicolor/ 2>/dev/null || true

# Restart Plasma so the new Plasmoid + icon appear
kquitapp6 plasmashell ; kstart plasmashell

# Add the widget to the main panel
qdbus org.kde.plasmashell /PlasmaShell evaluateScript '
  panels()[0].addWidget("org.bilbilak.claudebar");
'
```

### From the repo (developers)

From the repo root:

```sh
make build-helper        # builds claudebar-helper and puts it in apps/linux/common/claudebar-helper/target/release/
make install-helper      # copies it into ~/.local/bin
make install-kde         # runs `kpackagetool6 --install` and installs the icon to ~/.local/share/icons/
```

To uninstall:

```sh
make uninstall-kde
```

## Sign in

The Plasmoid popup has a **Sign in** button that invokes `claudebar-helper signin` — the browser opens, you complete the OAuth flow, and the widget starts showing your usage on the next poll.

Or from a terminal:

```sh
claudebar-helper signin
```

## How it polls

The Plasmoid uses `Plasma5Support.DataSource` (type `executable`) to run `claudebar-helper status` every `pollIntervalSeconds` seconds and parses the JSON output. No persistent daemon.

## Configuration

Right-click the Plasmoid → **Configure ClaudeBar** for:

- Poll interval (60–3600 s)
- Orange / red color thresholds
- Toggle numeric percentage labels
- Override `claudebar-helper` path if it's not in `$PATH`

## License

GPL-3.0-or-later.
