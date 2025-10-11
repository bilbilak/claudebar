# claudebar — LXQt panel plugin

C++/Qt plugin for **LXQt's** `lxqt-panel`. Two bars painted with `QPainter`. Delegates OAuth and token storage to [`claudebar-helper`](../common/claudebar-helper/). Builds against both Qt5 (LXQt 1.x) and Qt6 (LXQt 2.x, e.g. Lubuntu 25.04+).

## Build requirements

- `Qt5` or `Qt6` (Core, Gui, Widgets, LinguistTools)
- `liblxqt` (`liblxqt2-dev` on LXQt 2.x), `lxqt-build-tools`
- `cmake`, a C++17 compiler

Debian/Ubuntu (LXQt 1.x — Qt5): `sudo apt install liblxqt-dev lxqt-build-tools qtbase5-dev cmake`

Debian/Ubuntu (LXQt 2.x — Qt6): `sudo apt install qt6-base-dev qt6-base-dev-tools qt6-tools-dev liblxqt2-dev libkf6windowsystem-dev lxqt-build-tools cmake`

Arch: `sudo pacman -S liblxqt lxqt-build-tools qt6-base cmake`

## Install

From the repo root:

```sh
sudo make install-lxqt
```

Or step by step from this directory:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build
sudo cmake --install build
```

**`CMAKE_INSTALL_PREFIX=/usr` is required, not optional.** `lxqt-panel` only loads plugins from the compile-time-pinned `libdir/lxqt-panel/`. On Ubuntu / Mint that's `/usr/lib/x86_64-linux-gnu/lxqt-panel/`; nothing under `XDG_DATA_DIRS` is consulted. CMake's default `/usr/local` lands the plugin where the panel never looks.

Then add the **ClaudeBar** widget to the LXQt panel via **Configure Panel… → Widgets → +**.

Make sure `claudebar-helper` is also installed (see [`../common/claudebar-helper/`](../common/claudebar-helper/)). The plugin probes `$CLAUDEBAR_HELPER`, `$PATH`, `~/.local/bin`, `/usr/local/bin`, `/usr/bin`, and `/usr/libexec` at startup, so the default `make install-helper` location works without further configuration.

## License

GPL-3.0-or-later.
