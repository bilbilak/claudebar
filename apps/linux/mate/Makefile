PREFIX       ?= /usr/local
LIBEXECDIR    = $(PREFIX)/libexec
SERVICE_DIR   = $(PREFIX)/share/dbus-1/services
APPLET_DIR    = $(PREFIX)/share/mate-panel/applets

.PHONY: build install uninstall clean

build:
	@echo "MATE applet is pure Python; nothing to build."

install:
	install -Dm755 claudebar.py                                 $(DESTDIR)$(LIBEXECDIR)/claudebar.py
	sed "s|@LIBEXECDIR@|$(LIBEXECDIR)|g" \
	    org.mate.panel.applet.ClaudebarFactory.service          > /tmp/claudebar.service
	install -Dm644 /tmp/claudebar.service                       $(DESTDIR)$(SERVICE_DIR)/org.mate.panel.applet.ClaudebarFactory.service
	rm -f /tmp/claudebar.service
	install -Dm644 org.mate.panel.Claudebar.mate-panel-applet   $(DESTDIR)$(APPLET_DIR)/org.mate.panel.Claudebar.mate-panel-applet
	@echo ""
	@echo "Installed. Right-click the MATE panel → Add to panel → 'ClaudeBar'."

uninstall:
	rm -f $(DESTDIR)$(LIBEXECDIR)/claudebar.py
	rm -f $(DESTDIR)$(SERVICE_DIR)/org.mate.panel.applet.ClaudebarFactory.service
	rm -f $(DESTDIR)$(APPLET_DIR)/org.mate.panel.Claudebar.mate-panel-applet

clean:
	rm -rf __pycache__ *.pyc
