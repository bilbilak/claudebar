PREFIX       ?= /usr/local
LIBEXECDIR    = $(PREFIX)/libexec
SERVICE_DIR   = $(PREFIX)/share/dbus-1/services
APPLET_DIR    = $(PREFIX)/share/mate-panel/applets
LOCALE_DIR    = $(PREFIX)/share/locale
ICON_BASE     = $(PREFIX)/share/icons/hicolor
ICON_SRC_DIR  = ../common/icons
ICON_SIZES    = 16 22 24 32 48 64 128 256 512
GETTEXT_DOMAIN = claudebar-mate
USER_LOCALE_DIR = $(HOME)/.local/share/locale
PO_FILES := $(sort $(wildcard po/*.po))
PO_LANGS := $(patsubst po/%.po,%,$(PO_FILES))
REPO_ROOT  = ../../..
I18N_YAML  = $(REPO_ROOT)/i18n/strings.yaml
REGEN      = $(REPO_ROOT)/scripts/regenerate-translations.py

.PHONY: build install uninstall clean i18n mo-files

build: mo-files
	@echo "MATE applet is pure Python; only message catalogs were compiled."

i18n:
	@if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then \
	    python3 $(REGEN) mate; \
	elif command -v nix-shell >/dev/null 2>&1; then \
	    echo "python3+pyyaml not directly available; falling back to nix-shell."; \
	    nix-shell -p 'python3.withPackages (ps: [ps.pyyaml])' \
	        --run 'python3 $(REGEN) mate'; \
	else \
	    echo "error: need python3 with PyYAML, or nix-shell." >&2; \
	    exit 1; \
	fi

mo-files: $(patsubst po/%.po,po/%.mo,$(PO_FILES))

po/%.mo: po/%.po
	@command -v msgfmt >/dev/null 2>&1 || { \
	    echo "error: msgfmt not found (install the 'gettext' package)." >&2; \
	    exit 1; \
	}
	msgfmt -o $@ $<

install: mo-files
	install -Dm755 claudebar.py                                 $(DESTDIR)$(LIBEXECDIR)/claudebar.py
	sed "s|@LIBEXECDIR@|$(LIBEXECDIR)|g" \
	    org.mate.panel.applet.ClaudebarAppletFactory.service    > /tmp/claudebar.service
	install -Dm644 /tmp/claudebar.service                       $(DESTDIR)$(SERVICE_DIR)/org.mate.panel.applet.ClaudebarAppletFactory.service
	rm -f /tmp/claudebar.service
	install -Dm644 org.mate.panel.Claudebar.mate-panel-applet   $(DESTDIR)$(APPLET_DIR)/org.mate.panel.Claudebar.mate-panel-applet
	for sz in $(ICON_SIZES); do \
	    install -Dm644 $(ICON_SRC_DIR)/$${sz}x$${sz}/claudebar.png \
	        $(DESTDIR)$(ICON_BASE)/$${sz}x$${sz}/apps/claudebar.png; \
	done
	if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -z "$(DESTDIR)" ]; then \
	    gtk-update-icon-cache -f -q $(ICON_BASE) || true; \
	fi
	@for lang in $(PO_LANGS); do \
	    install -Dm644 po/$$lang.mo \
	        $(DESTDIR)$(LOCALE_DIR)/$$lang/LC_MESSAGES/$(GETTEXT_DOMAIN).mo; \
	done
	@echo ""
	@echo "Installed. Right-click the MATE panel → Add to panel → 'ClaudeBar'."

uninstall:
	rm -f $(DESTDIR)$(LIBEXECDIR)/claudebar.py
	rm -f $(DESTDIR)$(SERVICE_DIR)/org.mate.panel.applet.ClaudebarAppletFactory.service
	rm -f $(DESTDIR)$(SERVICE_DIR)/org.mate.panel.applet.ClaudebarFactory.service
	rm -f $(DESTDIR)$(APPLET_DIR)/org.mate.panel.Claudebar.mate-panel-applet
	for sz in $(ICON_SIZES); do \
	    rm -f $(DESTDIR)$(ICON_BASE)/$${sz}x$${sz}/apps/claudebar.png; \
	done
	@for lang in $(PO_LANGS); do \
	    rm -f $(DESTDIR)$(LOCALE_DIR)/$$lang/LC_MESSAGES/$(GETTEXT_DOMAIN).mo; \
	done

clean:
	rm -rf __pycache__ *.pyc po/*.mo
