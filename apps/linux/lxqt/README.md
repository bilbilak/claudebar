# claudebar — LXQt panel plugin

C++/Qt5 plugin for **LXQt's** `lxqt-panel`. Two bars painted with `QPainter`. Delegates OAuth and token storage to [`claudebar-helper`](../common/claudebar-helper/).

## Build requirements

- `Qt5` (Core, Gui, Widgets)
- `liblxqt`, `lxqt-build-tools`
- `cmake`, a C++17 compiler

Debian/Ubuntu: `sudo apt install liblxqt-dev lxqt-build-tools qtbase5-dev cmake`

Arch: `sudo pacman -S liblxqt lxqt-build-tools qt5-base cmake`

## Install

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build
```

Then add the "ClaudeBar" widget to the LXQt panel via **Configure Panel… → Widgets → +**.

Make sure `claudebar-helper` is also installed.

## License

GPL-3.0-or-later.
