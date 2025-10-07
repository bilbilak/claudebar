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
- **Debian / Ubuntu / Linux Mint**: `libdbus-1-3`, `libsecret-1-0`.
- **Fedora**: `dbus-libs`, `libsecret`.

Build-time:

- A recent stable **Rust** (≥ 1.75) — install via [`rustup`](https://rustup.rs/), not the system package; distro `rustc` is generally too old.
- The C development headers for the libraries the Rust crates wrap.

  - **Debian / Ubuntu / Linux Mint**: `sudo apt install build-essential pkg-config libdbus-1-dev libsecret-1-dev`
  - **Fedora**: `sudo dnf install gcc pkgconf-pkg-config dbus-devel libsecret-devel`
  - **openSUSE**: `sudo zypper install gcc pkgconf-pkg-config dbus-1-devel libsecret-devel`
  - **Arch**: `sudo pacman -S base-devel pkgconf` (dbus and libsecret are part of the standard install)

  Without these headers cargo will fail mid-build with `pkg-config exited with status code 1 / Package 'dbus-1' was not found` from `libdbus-sys`'s build script. `ksni` (the tray crate) and `secret-service` are the two consumers.

## Secret Service initialization

Sign-in completes the OAuth flow but immediately fails with `Error: getting default collection / SS error: result not returned from SS API` (or `connecting to Secret Service / The name org.freedesktop.secrets was not provided by any .service files`) when the system has no usable Secret Service backend. Common cases:

- **No daemon is running.** Lubuntu 25.x ships only the KDE compat shim (`org.kde.secretservicecompat`) without a daemon claiming `org.freedesktop.secrets`. Install gnome-keyring (`sudo apt install gnome-keyring libpam-gnome-keyring`) and log out / log in so PAM auto-starts it.
- **`gnome-keyring` runs but the default "Login" collection doesn't exist yet.** Solus / Lubuntu first-run state. Install `seahorse`, then **File → New → Password Keyring → "Login"** (capitalisation matters), leave the password blank, and **Set as Default**. Re-run `claudebar-helper signin` after that.

Run `claudebar-helper status` afterwards — it should report `"status":"ok"` instead of `"unauthenticated"`.

## License

GPL-3.0-or-later, same as the rest of claudebar.
