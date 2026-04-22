# claudebar — KDE Plasmoid

KDE Plasma 6 widget that shows your Claude.ai Max-plan session and weekly usage as two bars in the panel.

## Requirements

- **KDE Plasma 6.0+**
- **claudebar-helper** in `$PATH` (see [`apps/linux/common/claudebar-helper/`](../common/claudebar-helper/))
- A FreeDesktop Secret Service provider (KWallet is installed by default on KDE)

## Install

From the repo root:

```sh
make build-helper        # builds claudebar-helper and puts it in apps/linux/common/claudebar-helper/target/release/
make install-helper      # copies it into ~/.local/bin
make install-kde         # runs `kpackagetool6 --install`
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
