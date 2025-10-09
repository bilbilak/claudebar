PACKAGE_ID := org.bilbilak.claudebar
REPO_ROOT  := $(CURDIR)/../../..
REGEN      := $(REPO_ROOT)/scripts/regenerate-translations.py
PO_DIR     := $(CURDIR)/po
LANGS      := fr nl de es pt sv cs pl ru uk ar fa zh ja ko tr it hi
PLASMOID_LOCALE := $(HOME)/.local/share/plasma/plasmoids/$(PACKAGE_ID)/contents/locale
USER_LOCALE     := $(HOME)/.local/share/locale

.PHONY: build install uninstall package clean i18n install-translations uninstall-translations
.SILENT:

build:
	if command -v kpackagetool6 >/dev/null 2>&1; then \
	  kpackagetool6 --type=Plasma/Applet --show $(PACKAGE_ID) >/dev/null 2>&1 || true ; \
	  echo "Plasma 6 kpackagetool detected." ; \
	elif command -v kpackagetool5 >/dev/null 2>&1; then \
	  echo "Only Plasma 5 kpackagetool detected. Target is Plasma 6." ; \
	else \
	  echo "kpackagetool6 not found; skipping validation." ; \
	fi

i18n:
	if command -v python3 >/dev/null 2>&1; then \
	  python3 $(REGEN) kde ; \
	elif command -v nix-shell >/dev/null 2>&1; then \
	  nix-shell -p 'python3.withPackages (ps: [ps.pyyaml])' --run 'python3 $(REGEN) kde' ; \
	else \
	  echo "error: neither python3 nor nix-shell is available." ; \
	  exit 1 ; \
	fi

install: install-translations
	if command -v kpackagetool6 >/dev/null 2>&1; then \
	  kpackagetool6 --type=Plasma/Applet --install $(CURDIR) 2>/dev/null || \
	  kpackagetool6 --type=Plasma/Applet --upgrade $(CURDIR) ; \
	else \
	  echo "kpackagetool6 not found. Install KDE Plasma 6 development tools." ; \
	  exit 1 ; \
	fi
	mkdir -p $(HOME)/.local/share/icons/hicolor/256x256/apps/
	cp -f $(CURDIR)/contents/icons/claudebar.png \
	   $(HOME)/.local/share/icons/hicolor/256x256/apps/claudebar.png
	gtk-update-icon-cache -f $(HOME)/.local/share/icons/hicolor/ 2>/dev/null || true

install-translations:
	if [ ! -d "$(PO_DIR)" ]; then \
	  echo "po/ directory not found; run 'make i18n' first." ; \
	  exit 1 ; \
	fi
	if ! command -v msgfmt >/dev/null 2>&1; then \
	  echo "msgfmt not found. Install gettext (e.g. 'nix-shell -p gettext')." ; \
	  exit 1 ; \
	fi
	for lang in $(LANGS); do \
	  po="$(PO_DIR)/$$lang.po" ; \
	  if [ ! -f "$$po" ]; then \
	    echo "  skip $$lang (no $$po)" ; \
	    continue ; \
	  fi ; \
	  for dest in "$(PLASMOID_LOCALE)/$$lang/LC_MESSAGES" "$(USER_LOCALE)/$$lang/LC_MESSAGES" ; do \
	    mkdir -p "$$dest" ; \
	    msgfmt -o "$$dest/claudebar.mo" "$$po" ; \
	    echo "  installed $$dest/claudebar.mo" ; \
	  done ; \
	done

uninstall: uninstall-translations
	kpackagetool6 --type=Plasma/Applet --remove $(PACKAGE_ID)
	rm -f $(HOME)/.local/share/icons/hicolor/256x256/apps/claudebar.png
	gtk-update-icon-cache -f $(HOME)/.local/share/icons/hicolor/ 2>/dev/null || true

uninstall-translations:
	rm -rf $(PLASMOID_LOCALE)
	for lang in $(LANGS); do \
	  rm -f $(USER_LOCALE)/$$lang/LC_MESSAGES/claudebar.mo ; \
	done

package:
	mkdir -p dist
	rm -f dist/claudebar-kde.plasmoid
	rm -rf $(CURDIR)/contents/locale
	if [ -d "$(PO_DIR)" ] && command -v msgfmt >/dev/null 2>&1; then \
	  for lang in $(LANGS); do \
	    po="$(PO_DIR)/$$lang.po" ; \
	    [ -f "$$po" ] || continue ; \
	    dest="$(CURDIR)/contents/locale/$$lang/LC_MESSAGES" ; \
	    mkdir -p "$$dest" ; \
	    msgfmt -o "$$dest/claudebar.mo" "$$po" ; \
	  done ; \
	else \
	  echo "warning: po/ missing or msgfmt unavailable — .plasmoid will ship without translations." ; \
	fi
	zip -r dist/claudebar-kde.plasmoid metadata.json contents/
	rm -rf $(CURDIR)/contents/locale

clean:
	rm -rf dist
	rm -rf $(CURDIR)/contents/locale
