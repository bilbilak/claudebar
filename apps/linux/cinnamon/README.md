# claudebar — Cinnamon applet

Panel applet for **Linux Mint's Cinnamon desktop** (also available on other distros via `cinnamon`). Shows Claude.ai Max-plan session and weekly usage as two bars directly in the panel.

Shares the libsecret token storage (`org.bilbilak.claudebar` schema) with the GNOME extension — so if you've signed in via one, the other picks it up.

## Install

```sh
make install                # copies to ~/.local/share/cinnamon/applets/
```

Then: right-click the Cinnamon panel → **Applets** → enable **ClaudeBar**.

## Sign in

Right-click the applet → **Configure…** → **Account** → **Sign in with Claude…**.

## Supported Cinnamon versions

`5.0`, `5.2`, `5.4`, `6.0`, `6.2`, `6.4`.

## License

GPL-3.0-or-later.
