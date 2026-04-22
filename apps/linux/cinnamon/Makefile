UUID := claudebar@bilbilak.org
INSTALL_DIR := $(HOME)/.local/share/cinnamon/applets/$(UUID)

.PHONY: build install uninstall pack clean

build:
	@echo "Cinnamon applet is pure JS + JSON; nothing to build."

install:
	rm -rf $(INSTALL_DIR)
	mkdir -p $(INSTALL_DIR)
	cp metadata.json $(INSTALL_DIR)/
	cp applet.js $(INSTALL_DIR)/
	cp api.js $(INSTALL_DIR)/
	cp auth.js $(INSTALL_DIR)/
	cp oauth.js $(INSTALL_DIR)/
	cp settings-schema.json $(INSTALL_DIR)/
	cp stylesheet.css $(INSTALL_DIR)/
	@echo ""
	@echo "Installed -> $(INSTALL_DIR)"
	@echo "Enable via: cinnamon-settings applets → Download tab isn't needed for locally-installed applets."
	@echo "Add to panel: right-click panel → Applets → Manage → enable 'ClaudeBar'."

uninstall:
	rm -rf $(INSTALL_DIR)

pack:
	mkdir -p dist
	zip -r dist/$(UUID).zip \
	    metadata.json applet.js api.js auth.js oauth.js \
	    settings-schema.json stylesheet.css

clean:
	rm -rf dist
