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
        clean-xfce clean-mate clean-budgie clean-lxqt \
        i18n i18n-gnome i18n-kde i18n-cinnamon i18n-xfce i18n-mate \
        i18n-budgie i18n-lxqt i18n-helper i18n-macos \
        i18n-windows i18n-wix

## help                       Show this help (default target).
help:
	@awk '/^## / { sub(/^## /, ""); print }' $(MAKEFILE_LIST)

## setup                      Install JS deps for the GNOME extension.
setup:
	cd $(LINUX_GNOME) && npm ci

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

## build-linux                Build every Linux front-end + helper.
build-linux: build-helper build-gnome build-kde build-cinnamon build-xfce build-mate build-budgie build-lxqt

## pack-linux                 Produce distributable zips/packages for every Linux front-end.
pack-linux: pack-helper pack-gnome pack-kde pack-cinnamon

## build-helper               `cargo build --release` the shared claudebar-helper.
build-helper:
	$(MAKE) -C $(LINUX_HELPER) build

## install-helper             Copy claudebar-helper into ~/.local/bin and install translation .mo files.
install-helper: build-helper
	install -Dm755 $(LINUX_HELPER)/target/release/claudebar-helper \
	               $(HOME)/.local/bin/claudebar-helper
	$(MAKE) -C $(LINUX_HELPER) install
	@echo "Installed claudebar-helper -> $(HOME)/.local/bin/claudebar-helper"

## pack-helper                Produce a stripped release binary at helper/dist/.
pack-helper: build-helper
	@mkdir -p $(LINUX_HELPER)/dist
	cp $(LINUX_HELPER)/target/release/claudebar-helper $(LINUX_HELPER)/dist/
	@echo "Packed -> $(LINUX_HELPER)/dist/claudebar-helper"

clean-helper:
	cd $(LINUX_HELPER) && cargo clean
	rm -rf $(LINUX_HELPER)/dist

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

## build-xfce                 meson setup + compile the XFCE plugin.
build-xfce:
	$(MAKE) -C $(LINUX_XFCE) build

## install-xfce               sudo meson install the XFCE plugin.
install-xfce:
	$(MAKE) -C $(LINUX_XFCE) install

clean-xfce:
	$(MAKE) -C $(LINUX_XFCE) clean

## build-mate                 No-op (MATE applet is pure Python).
build-mate:
	$(MAKE) -C $(LINUX_MATE) build

## install-mate               Install Python applet + D-Bus service + mate-panel-applet file.
install-mate:
	$(MAKE) -C $(LINUX_MATE) install

clean-mate:
	$(MAKE) -C $(LINUX_MATE) clean

## build-budgie               meson setup + compile the Budgie applet.
build-budgie:
	$(MAKE) -C $(LINUX_BUDGIE) build

## install-budgie             sudo meson install the Budgie applet.
install-budgie:
	$(MAKE) -C $(LINUX_BUDGIE) install

clean-budgie:
	$(MAKE) -C $(LINUX_BUDGIE) clean

## build-lxqt                 cmake build the LXQt plugin.
build-lxqt:
	$(MAKE) -C $(LINUX_LXQT) build

## install-lxqt               sudo cmake --install the LXQt plugin.
install-lxqt:
	$(MAKE) -C $(LINUX_LXQT) install

clean-lxqt:
	$(MAKE) -C $(LINUX_LXQT) clean

## build-macos                `swift build -c release` the macOS app.
build-macos:
	$(MAKE) -C $(MACOS_DIR) build

## pack-macos                 Build and bundle apps/macos/dist/ClaudeBar.app.
pack-macos:
	$(MAKE) -C $(MACOS_DIR) bundle

clean-macos:
	$(MAKE) -C $(MACOS_DIR) clean

## build-windows              `dotnet build -c Release`.
build-windows:
	cd $(WINDOWS_DIR) && dotnet build -c Release

## pack-windows               `dotnet publish -c Release -r win-x64 -o publish`.
pack-windows:
	cd $(WINDOWS_DIR) && dotnet publish -c Release -r win-x64 --self-contained false -o publish

clean-windows:
	rm -rf $(WINDOWS_DIR)/bin $(WINDOWS_DIR)/obj $(WINDOWS_DIR)/publish

## clean                      Remove build artifacts across every app.
clean: clean-helper clean-gnome clean-kde clean-cinnamon \
       clean-xfce clean-mate clean-budgie clean-lxqt \
       clean-macos clean-windows

REGEN := scripts/regenerate-translations.py

define run_regen
	@if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then \
	    python3 $(REGEN) $(1); \
	elif command -v nix-shell >/dev/null 2>&1; then \
	    nix-shell -p 'python3.withPackages (ps: [ps.pyyaml])' \
	        --run 'python3 $(REGEN) $(1)'; \
	else \
	    echo "error: python3 with PyYAML, or nix-shell, is required to run the regen script." >&2; \
	    exit 1; \
	fi
endef

## i18n                       Regenerate translation files for every platform.
i18n:
	$(call run_regen,--all)

## i18n-gnome                 Regenerate GNOME extension .po files.
i18n-gnome:
	$(call run_regen,gnome)

## i18n-kde                   Regenerate KDE Plasmoid .po files.
i18n-kde:
	$(call run_regen,kde)

## i18n-cinnamon              Regenerate Cinnamon applet .po files.
i18n-cinnamon:
	$(call run_regen,cinnamon)

## i18n-xfce                  Regenerate XFCE plugin .po files.
i18n-xfce:
	$(call run_regen,xfce)

## i18n-mate                  Regenerate MATE applet .po files.
i18n-mate:
	$(call run_regen,mate)

## i18n-budgie                Regenerate Budgie applet .po files.
i18n-budgie:
	$(call run_regen,budgie)

## i18n-lxqt                  Regenerate LXQt plugin .ts files.
i18n-lxqt:
	$(call run_regen,lxqt)

## i18n-helper                Regenerate Rust helper .po files.
i18n-helper:
	$(call run_regen,helper)

## i18n-macos                 Regenerate macOS Localizable.xcstrings.
i18n-macos:
	$(call run_regen,macos)

## i18n-windows               Regenerate Windows .resx files.
i18n-windows:
	$(call run_regen,windows)

## i18n-wix                   Regenerate WiX installer .wxl files.
i18n-wix:
	$(call run_regen,wix)
