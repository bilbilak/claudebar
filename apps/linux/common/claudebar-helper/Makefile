DOMAIN := claudebar-helper
REGEN := ../../../../scripts/regenerate-translations.py
PO_DIR := po
LOCALE_INSTALL_DIR := $(HOME)/.local/share/locale
LANGS := fr nl de es pt sv cs pl ru uk ar fa zh ja ko tr it hi

.PHONY: build i18n install uninstall-locales clean

build: i18n
	cargo build --release

i18n:
	@if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then \
		python3 $(REGEN) helper; \
	else \
		nix-shell -p 'python3.withPackages (ps: [ps.pyyaml])' --run 'python3 $(REGEN) helper'; \
	fi

install:
	@command -v msgfmt >/dev/null 2>&1 || { \
		echo "msgfmt not found — install gettext to enable translated UI."; \
		exit 0; \
	}
	@for lang in $(LANGS); do \
		po="$(PO_DIR)/$$lang.po"; \
		if [ -f "$$po" ]; then \
			dest="$(LOCALE_INSTALL_DIR)/$$lang/LC_MESSAGES"; \
			mkdir -p "$$dest"; \
			msgfmt -o "$$dest/$(DOMAIN).mo" "$$po"; \
			echo "Installed $$dest/$(DOMAIN).mo"; \
		fi; \
	done

uninstall-locales:
	@for lang in $(LANGS); do \
		rm -f "$(LOCALE_INSTALL_DIR)/$$lang/LC_MESSAGES/$(DOMAIN).mo"; \
	done

clean:
	cargo clean
