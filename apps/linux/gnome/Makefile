UUID := claudebar@bilbilak.org
EXT_DIR := $(HOME)/.local/share/gnome-shell/extensions/$(UUID)
REGEN := ../../../scripts/regenerate-translations.py

.PHONY: build install uninstall pack clean enable disable logs i18n

i18n:
	@if command -v python3 >/dev/null 2>&1; then \
		python3 $(REGEN) gnome; \
	else \
		nix-shell -p 'python3.withPackages (ps: [ps.pyyaml])' --run 'python3 $(REGEN) gnome'; \
	fi

build: i18n
	npm run build

install: build
	rm -rf $(EXT_DIR)
	mkdir -p $(EXT_DIR)
	cp -r dist/* $(EXT_DIR)/
	@echo ""
	@echo "Installed to $(EXT_DIR)"
	@echo "Restart GNOME Shell: log out and back in (or Alt+F2 'r' on X11)."
	@echo "Then enable: gnome-extensions enable $(UUID)"

uninstall:
	rm -rf $(EXT_DIR)

enable:
	gnome-extensions enable $(UUID)

disable:
	gnome-extensions disable $(UUID)

pack: build
	cd dist && zip -r ../$(UUID).shell-extension.zip .

logs:
	journalctl --user -f -o cat /usr/bin/gnome-shell

clean:
	rm -rf dist *.zip
