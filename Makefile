# claudebar — cross-platform Claude.ai usage indicator.
# Top-level Makefile that dispatches to each app's native toolchain.

UNAME_S := $(shell uname -s 2>/dev/null)

LINUX_GNOME   := apps/linux/gnome
LINUX_KDE     := apps/linux/kde
LINUX_CINN    := apps/linux/cinnamon
LINUX_XFCE    := apps/linux/xfce
LINUX_MATE    := apps/linux/mate
LINUX_BUDGIE  := apps/linux/budgie
LINUX_LXQT    := apps/linux/lxqt
LINUX_HELPER  := apps/linux/common/claudebar-helper
MACOS_DIR     := apps/macos
WINDOWS_DIR   := apps/windows

.PHONY: help setup \
        build build-linux build-macos build-windows \
        build-helper build-gnome build-kde build-cinnamon \
        build-xfce build-mate build-budgie build-lxqt \
        pack pack-linux pack-macos pack-windows \
        pack-helper pack-gnome pack-kde pack-cinnamon \
        install-helper install-gnome install-kde install-cinnamon \
        install-xfce install-mate install-budgie install-lxqt \
        enable-gnome disable-gnome logs-gnome \
        clean clean-linux clean-macos clean-windows \
        clean-helper clean-gnome clean-kde clean-cinnamon \
        clean-xfce clean-mate clean-budgie clean-lxqt

## help                       Show this help (default target).
help:
	@awk '/^## / { sub(/^## /, ""); print }' $(MAKEFILE_LIST)

## setup                      Install JS deps for the GNOME extension.
setup:
	cd $(LINUX_GNOME) && npm ci

# ---------------------------------------------------------------------------
# Host-platform aliases — `make build` / `make pack` on the current OS.
# ---------------------------------------------------------------------------

## build                      Build everything appropriate for the host platform.
build:
	@case "$(UNAME_S)" in \
	  Linux)  $(MAKE) build-linux ;; \
	  Darwin) $(MAKE) build-macos ;; \
	  MINGW*|MSYS*|CYGWIN*) $(MAKE) build-windows ;; \
	  *) echo "Unknown host '$(UNAME_S)'; use build-<platform>."; exit 1 ;; \
	esac

## pack                       Package release artifacts appropriate for the host platform.
pack:
	@case "$(UNAME_S)" in \
	  Linux)  $(MAKE) pack-linux ;; \
	  Darwin) $(MAKE) pack-macos ;; \
	  MINGW*|MSYS*|CYGWIN*) $(MAKE) pack-windows ;; \
	  *) echo "Unknown host '$(UNAME_S)'; use pack-<platform>."; exit 1 ;; \
	esac

# ---------------------------------------------------------------------------
# Linux aggregate
# ---------------------------------------------------------------------------

## build-linux                Build every Linux front-end + helper.
build-linux: build-helper build-gnome build-kde build-cinnamon build-xfce build-mate build-budgie build-lxqt

## pack-linux                 Produce distributable zips/packages for every Linux front-end.
pack-linux: pack-helper pack-gnome pack-kde pack-cinnamon

# ---------------------------------------------------------------------------
# Shared Rust helper
# ---------------------------------------------------------------------------

## build-helper               `cargo build --release` the shared claudebar-helper.
build-helper:
	cd $(LINUX_HELPER) && cargo build --release

## install-helper             Copy claudebar-helper into ~/.local/bin (user install).
install-helper: build-helper
	install -Dm755 $(LINUX_HELPER)/target/release/claudebar-helper \
	               $(HOME)/.local/bin/claudebar-helper
	@echo "Installed claudebar-helper -> $(HOME)/.local/bin/claudebar-helper"

## pack-helper                Produce a stripped release binary at helper/dist/.
pack-helper: build-helper
	@mkdir -p $(LINUX_HELPER)/dist
	cp $(LINUX_HELPER)/target/release/claudebar-helper $(LINUX_HELPER)/dist/
	@echo "Packed -> $(LINUX_HELPER)/dist/claudebar-helper"

clean-helper:
	cd $(LINUX_HELPER) && cargo clean
	rm -rf $(LINUX_HELPER)/dist

# ---------------------------------------------------------------------------
# GNOME Shell extension
# ---------------------------------------------------------------------------

## build-gnome                Build the GNOME Shell extension bundle.
build-gnome:
	$(MAKE) -C $(LINUX_GNOME) build

## pack-gnome                 Zip the GNOME extension for upload.
pack-gnome:
	$(MAKE) -C $(LINUX_GNOME) pack

## install-gnome              Install the GNOME extension into ~/.local/share.
install-gnome:
	$(MAKE) -C $(LINUX_GNOME) install

## enable-gnome               gnome-extensions enable claudebar@bilbilak.org
enable-gnome:
	$(MAKE) -C $(LINUX_GNOME) enable

## disable-gnome              gnome-extensions disable claudebar@bilbilak.org
disable-gnome:
	$(MAKE) -C $(LINUX_GNOME) disable

## logs-gnome                 Tail the live gnome-shell journal.
logs-gnome:
	$(MAKE) -C $(LINUX_GNOME) logs

clean-gnome:
	$(MAKE) -C $(LINUX_GNOME) clean

# ---------------------------------------------------------------------------
# KDE Plasmoid
# ---------------------------------------------------------------------------

## build-kde                  Validate the KDE Plasmoid structure (no compile step).
build-kde:
	$(MAKE) -C $(LINUX_KDE) build

## pack-kde                   Produce a .plasmoid tarball.
pack-kde:
	$(MAKE) -C $(LINUX_KDE) package

## install-kde                kpackagetool6 --install ./apps/linux/kde
install-kde:
	$(MAKE) -C $(LINUX_KDE) install

clean-kde:
	$(MAKE) -C $(LINUX_KDE) clean

# ---------------------------------------------------------------------------
# Cinnamon applet
# ---------------------------------------------------------------------------

## build-cinnamon             No-op (Cinnamon applet is pure JS).
build-cinnamon:
	$(MAKE) -C $(LINUX_CINN) build

## pack-cinnamon              Zip the Cinnamon applet into dist/.
pack-cinnamon:
	$(MAKE) -C $(LINUX_CINN) pack

## install-cinnamon           Install into ~/.local/share/cinnamon/applets/.
install-cinnamon:
	$(MAKE) -C $(LINUX_CINN) install

clean-cinnamon:
	$(MAKE) -C $(LINUX_CINN) clean

# ---------------------------------------------------------------------------
# XFCE panel plugin (meson + C)
# ---------------------------------------------------------------------------

## build-xfce                 meson setup + compile the XFCE plugin.
build-xfce:
	$(MAKE) -C $(LINUX_XFCE) build

## install-xfce               sudo meson install the XFCE plugin.
install-xfce:
	$(MAKE) -C $(LINUX_XFCE) install

clean-xfce:
	$(MAKE) -C $(LINUX_XFCE) clean

# ---------------------------------------------------------------------------
# MATE applet (Python)
# ---------------------------------------------------------------------------

## build-mate                 No-op (MATE applet is pure Python).
build-mate:
	$(MAKE) -C $(LINUX_MATE) build

## install-mate               Install Python applet + D-Bus service + mate-panel-applet file.
install-mate:
	$(MAKE) -C $(LINUX_MATE) install

clean-mate:
	$(MAKE) -C $(LINUX_MATE) clean

# ---------------------------------------------------------------------------
# Budgie applet (Vala + meson)
# ---------------------------------------------------------------------------

## build-budgie               meson setup + compile the Budgie applet.
build-budgie:
	$(MAKE) -C $(LINUX_BUDGIE) build

## install-budgie             sudo meson install the Budgie applet.
install-budgie:
	$(MAKE) -C $(LINUX_BUDGIE) install

clean-budgie:
	$(MAKE) -C $(LINUX_BUDGIE) clean

# ---------------------------------------------------------------------------
# LXQt plugin (C++/Qt5 + cmake)
# ---------------------------------------------------------------------------

## build-lxqt                 cmake build the LXQt plugin.
build-lxqt:
	$(MAKE) -C $(LINUX_LXQT) build

## install-lxqt               sudo cmake --install the LXQt plugin.
install-lxqt:
	$(MAKE) -C $(LINUX_LXQT) install

clean-lxqt:
	$(MAKE) -C $(LINUX_LXQT) clean

# ---------------------------------------------------------------------------
# macOS
# ---------------------------------------------------------------------------

## build-macos                `swift build -c release` the macOS app.
build-macos:
	$(MAKE) -C $(MACOS_DIR) build

## pack-macos                 Build and bundle apps/macos/dist/ClaudeBar.app.
pack-macos:
	$(MAKE) -C $(MACOS_DIR) bundle

clean-macos:
	$(MAKE) -C $(MACOS_DIR) clean

# ---------------------------------------------------------------------------
# Windows (.NET 8 WPF)
# ---------------------------------------------------------------------------

## build-windows              `dotnet build -c Release`.
build-windows:
	cd $(WINDOWS_DIR) && dotnet build -c Release

## pack-windows               `dotnet publish -c Release -r win-x64 -o publish`.
pack-windows:
	cd $(WINDOWS_DIR) && dotnet publish -c Release -r win-x64 --self-contained false -o publish

clean-windows:
	rm -rf $(WINDOWS_DIR)/bin $(WINDOWS_DIR)/obj $(WINDOWS_DIR)/publish

# ---------------------------------------------------------------------------
# Aggregate clean
# ---------------------------------------------------------------------------

## clean                      Remove build artifacts across every app.
clean: clean-helper clean-gnome clean-kde clean-cinnamon \
       clean-xfce clean-mate clean-budgie clean-lxqt \
       clean-macos clean-windows
