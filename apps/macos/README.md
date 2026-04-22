# ClaudeBar — macOS menu bar app

Menu bar app that shows your Claude.ai Max-plan session and weekly usage, mirroring the [GNOME extension](../claudebar-gnome-extension).

- Two stacked bars in the menu bar (current 5-hour session + 7-day weekly).
- Click to open a menu with percentages, reset times, refresh, and link to claude.ai.
- Sign in with Claude via OAuth (PKCE); tokens are stored in the macOS Keychain.
- Configurable poll interval and color thresholds.

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (`xcode-select --install`) — provides Swift 5.9+

## Build

```sh
make bundle          # builds and packages dist/ClaudeBar.app
open dist/ClaudeBar.app
```

Or install into `/Applications`:

```sh
make install
```

## Develop

```sh
swift build          # debug build, binary at .build/debug/ClaudeBar
swift run            # build & launch (no .app bundle — menu bar icon will still show)
```

To open the sources in Xcode:

```sh
open Package.swift
```

## Sign in

1. Launch the app — a menu bar icon with two bars appears.
2. Click the icon → **Settings…**
3. On the **Account** tab, click **Sign in with Claude**. Your browser opens to claude.ai.
4. Complete sign-in. The tab will say "Signed in" and the bars will update within a minute.

Tokens are encrypted at rest in the default Keychain (`org.bilbilak.claudebar`).

## Uninstall

```sh
rm -rf /Applications/ClaudeBar.app
security delete-generic-password -s org.bilbilak.claudebar || true
defaults delete org.bilbilak.claudebar || true
```
