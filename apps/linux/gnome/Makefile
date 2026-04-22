UUID := claudebar@bilbilak.org
EXT_DIR := $(HOME)/.local/share/gnome-shell/extensions/$(UUID)

.PHONY: build install uninstall pack clean enable disable logs

build:
	npm run build

install: build
	rm -rf $(EXT_DIR)
	mkdir -p $(EXT_DIR)
	cp -r dist/* $(EXT_DIR)/
	@echo ""
	@echo "Installed to $(EXT_DIR)"
	@echo "Restart GNOME Shell: log out and log back in (or Alt+F2 'r' on X11)."
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
