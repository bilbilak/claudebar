# claudebar-helper

A small Rust CLI that shared code between the non-GNOME Linux front-ends (KDE Plasmoid, Cinnamon/XFCE/MATE/Budgie/LXQt applets). It:

- runs the OAuth PKCE sign-in flow via a loopback HTTP listener,
- stores tokens in the FreeDesktop Secret Service (GNOME Keyring, KWallet, KeePassXC…),
- fetches the current usage snapshot on demand, printing JSON on stdout,
- optionally runs as a cross-DE StatusNotifierItem tray, rendering the two bars into the icon.

The GNOME Shell extension (`apps/linux/gnome/`) does not depend on this helper — it has its own GJS equivalents of all three things.

## Subcommands

```sh
claudebar-helper signin        # OAuth flow, stores tokens
claudebar-helper signout       # clears stored tokens
claudebar-helper status        # prints one JSON line: {"session":{"percent":...,"resets_at":...},...}
claudebar-helper tray --interval 300   # run as an SNI tray with bars as the icon
```

Front-ends typically run `claudebar-helper status` on their poll interval and render the returned JSON in their panel-native UI.

## Build

```sh
cargo build --release
# or
make -C ../.. build-helper
```

## Dependencies

Runtime packages you'll want on a target machine:

- **Arch**: none beyond a standard desktop (Secret Service is provided by `gnome-keyring` or `kwallet`, both usually installed).
- **Debian/Ubuntu**: `libdbus-1-3`, `libsecret-1-0`.
- **Fedora**: `dbus-libs`, `libsecret`.

Build-time: a recent stable Rust (≥ 1.75).

## License

GPL-3.0-or-later, same as the rest of claudebar.
