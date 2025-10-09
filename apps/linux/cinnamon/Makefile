UUID := claudebar@bilbilak.org
INSTALL_DIR := $(HOME)/.local/share/cinnamon/applets/$(UUID)
LOCALE_DIR := $(HOME)/.local/share/locale
REPO_ROOT := $(realpath $(CURDIR)/../../..)
PO_DIR := po
LANGS := fr nl de es pt sv cs pl ru uk ar fa zh ja ko tr it hi

PYTHON_OK := $(shell command -v python3 >/dev/null 2>&1 && echo yes)
ifeq ($(PYTHON_OK),yes)
    REGEN := python3 $(REPO_ROOT)/scripts/regenerate-translations.py cinnamon
else
    REGEN := nix-shell -p 'python3.withPackages (ps: [ps.pyyaml])' --run 'python3 $(REPO_ROOT)/scripts/regenerate-translations.py cinnamon'
endif

.PHONY: build install uninstall pack clean i18n install-mo uninstall-mo

build:
	@echo "Cinnamon applet is pure JS + JSON; nothing to build."

i18n:
	@echo "Regenerating Cinnamon translation catalogs from i18n/strings.yaml..."
	$(REGEN)

install-mo:
	@command -v msgfmt >/dev/null 2>&1 || { \
	    echo "error: 'msgfmt' is required to compile .po files (install the 'gettext' package)" >&2; \
	    exit 1; \
	}
	@for lang in $(LANGS); do \
	    src="$(PO_DIR)/$$lang.po"; \
	    if [ -f "$$src" ]; then \
	        dest_dir="$(LOCALE_DIR)/$$lang/LC_MESSAGES"; \
	        mkdir -p "$$dest_dir"; \
	        msgfmt --check -o "$$dest_dir/$(UUID).mo" "$$src" && \
	            echo "  compiled $$src -> $$dest_dir/$(UUID).mo"; \
	    else \
	        echo "  (skip) $$src missing — run 'make i18n' first"; \
	    fi; \
	done

uninstall-mo:
	@for lang in $(LANGS); do \
	    mo="$(LOCALE_DIR)/$$lang/LC_MESSAGES/$(UUID).mo"; \
	    if [ -f "$$mo" ]; then \
	        rm -f "$$mo" && echo "  removed $$mo"; \
	    fi; \
	done

install: install-mo
	rm -rf $(INSTALL_DIR)
	mkdir -p $(INSTALL_DIR)
	cp metadata.json $(INSTALL_DIR)/
	cp applet.js $(INSTALL_DIR)/
	cp api.js $(INSTALL_DIR)/
	cp auth.js $(INSTALL_DIR)/
	cp oauth.js $(INSTALL_DIR)/
	cp settings-schema.json $(INSTALL_DIR)/
	cp stylesheet.css $(INSTALL_DIR)/
	cp icon.png $(INSTALL_DIR)/
	@if [ -d $(PO_DIR) ]; then \
	    mkdir -p $(INSTALL_DIR)/po; \
	    cp $(PO_DIR)/*.po $(PO_DIR)/*.pot $(INSTALL_DIR)/po/ 2>/dev/null || true; \
	fi
	@echo ""
	@echo "Installed -> $(INSTALL_DIR)"
	@echo "Translations compiled into $(LOCALE_DIR)/<lang>/LC_MESSAGES/$(UUID).mo"
	@echo "Enable via: cinnamon-settings applets → Download tab isn't needed for locally-installed applets."
	@echo "Add to panel: right-click panel → Applets → Manage → enable 'ClaudeBar'."

uninstall: uninstall-mo
	rm -rf $(INSTALL_DIR)

pack: i18n
	mkdir -p dist
	rm -rf dist/locale
	@command -v msgfmt >/dev/null 2>&1 || { \
	    echo "error: 'msgfmt' is required to bundle translations" >&2; \
	    exit 1; \
	}
	@for lang in $(LANGS); do \
	    src="$(PO_DIR)/$$lang.po"; \
	    if [ -f "$$src" ]; then \
	        dest_dir="dist/locale/$$lang/LC_MESSAGES"; \
	        mkdir -p "$$dest_dir"; \
	        msgfmt --check -o "$$dest_dir/$(UUID).mo" "$$src"; \
	    fi; \
	done
	zip -r dist/$(UUID).zip \
	    metadata.json applet.js api.js auth.js oauth.js \
	    settings-schema.json stylesheet.css icon.png \
	    $(PO_DIR) \
	    -x '$(PO_DIR)/*.mo'
	cd dist && zip -r $(UUID).zip locale

clean:
	rm -rf dist
