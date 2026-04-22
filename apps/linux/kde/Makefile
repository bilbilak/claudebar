PACKAGE_ID := org.bilbilak.claudebar

.PHONY: build install uninstall package clean

# The Plasmoid is pure QML + metadata; "build" just validates the package.
build:
	@if command -v kpackagetool6 >/dev/null 2>&1; then \
	  kpackagetool6 --type=Plasma/Applet --show $(PACKAGE_ID) >/dev/null 2>&1 || true ; \
	  echo "Plasma 6 kpackagetool detected." ; \
	elif command -v kpackagetool5 >/dev/null 2>&1; then \
	  echo "Only Plasma 5 kpackagetool detected. Target is Plasma 6." ; \
	else \
	  echo "kpackagetool6 not found; skipping validation." ; \
	fi

install:
	@if command -v kpackagetool6 >/dev/null 2>&1; then \
	  kpackagetool6 --type=Plasma/Applet --install $(CURDIR) 2>/dev/null || \
	  kpackagetool6 --type=Plasma/Applet --upgrade $(CURDIR) ; \
	else \
	  echo "kpackagetool6 not found. Install KDE Plasma 6 development tools." ; \
	  exit 1 ; \
	fi

uninstall:
	kpackagetool6 --type=Plasma/Applet --remove $(PACKAGE_ID)

package:
	mkdir -p dist
	tar -czf dist/claudebar-kde.plasmoid \
	    metadata.json \
	    contents/

clean:
	rm -rf dist
