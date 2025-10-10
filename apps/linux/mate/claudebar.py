#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# claudebar — MATE panel applet.
#
# Shells out to `claudebar-helper status` for data and renders two bars
# via GTK3 + Cairo. Does not implement OAuth itself — right-click
# "Sign in…" delegates to `claudebar-helper signin`.

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("MatePanelApplet", "4.0")

from gi.repository import Gtk, Gio, GLib, MatePanelApplet
import gettext
import json
import math
import os
import shutil
import subprocess
import sys


# Strings live in apps/linux/mate/po/, compiled to claudebar-mate.mo and
# installed under either:
#   - ~/.local/share/locale/<lang>/LC_MESSAGES/  (per-user `make install`), or
#   - $PREFIX/share/locale/<lang>/LC_MESSAGES/   (system-wide install).
# We try the per-user dir first; if no catalogue is found, we fall back to
# gettext's default search path (which covers /usr/share/locale,
# /usr/local/share/locale, $LOCPATH, etc.).
_TRANSLATION_DOMAIN = "claudebar-mate"
_LOCALE_DIR = os.path.expanduser("~/.local/share/locale")


def _load_translation():
    user = gettext.translation(_TRANSLATION_DOMAIN, localedir=_LOCALE_DIR, fallback=True)
    # gettext.translation() returns a NullTranslations when nothing matches.
    # If we got nothing for the per-user dir, retry against the system path
    # (localedir=None -> use gettext default search path).
    if isinstance(user, gettext.NullTranslations) and not isinstance(user, gettext.GNUTranslations):
        return gettext.translation(_TRANSLATION_DOMAIN, fallback=True)
    return user


_ = _load_translation().gettext

DEFAULT_INTERVAL = 300
DEFAULT_WARN = 60
DEFAULT_CRIT = 85
BAR_WIDTH = 64
BAR_HEIGHT = 6
BAR_GAP = 4

# Locations to probe for claudebar-helper when it isn't on $PATH. mate-panel
# activates the applet over the session bus, and the session-bus daemon's
# PATH is fixed at session start — it almost never includes ~/.local/bin on
# Ubuntu/Mint, even though the user's interactive shell does. The helper is
# user-installed there by default (top-level `make install-helper`), so a
# naive `subprocess.Popen("claudebar-helper")` raises FileNotFoundError and
# every menu action silently no-ops. Probe the obvious fallback locations
# before giving up.
HELPER_FALLBACK_DIRS = [
    os.path.expanduser("~/.local/bin"),
    "/usr/local/bin",
    "/usr/bin",
    "/usr/libexec",
]


def _resolve_helper():
    """Find claudebar-helper, preferring $CLAUDEBAR_HELPER, then $PATH, then
    well-known install locations. Returns an absolute path, or the bare name
    "claudebar-helper" as a last resort so callers still get a useful error
    message in journalctl when it really is missing.
    """
    env = os.environ.get("CLAUDEBAR_HELPER")
    if env and os.path.isfile(env) and os.access(env, os.X_OK):
        return env
    path_hit = shutil.which("claudebar-helper")
    if path_hit:
        return path_hit
    for d in HELPER_FALLBACK_DIRS:
        candidate = os.path.join(d, "claudebar-helper")
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return "claudebar-helper"


# Per-user config lives alongside other ClaudeBar state under XDG_CONFIG_HOME.
# JSON rather than GSettings to avoid the gschema compile/install ceremony for
# four scalar fields — the same approach the helper uses for its own state.
CONFIG_PATH = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
    "claudebar", "mate.json",
)


def _load_config():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}
    return data if isinstance(data, dict) else {}


def _save_config(cfg):
    try:
        os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
        with open(CONFIG_PATH, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh, indent=2)
    except OSError as e:
        sys.stderr.write("claudebar: failed to save config %r: %s\n" % (CONFIG_PATH, e))
        sys.stderr.flush()


class Claudebar:
    def __init__(self, applet):
        self.applet = applet
        cfg = _load_config()
        self.poll_interval = int(cfg.get("poll_interval", DEFAULT_INTERVAL))
        self.warn = int(cfg.get("warn", DEFAULT_WARN))
        self.crit = int(cfg.get("crit", DEFAULT_CRIT))
        helper_override = cfg.get("helper_path")
        self.helper_path = helper_override if helper_override else _resolve_helper()
        self.snapshot = None
        self.status = "offline"

        self.drawing = Gtk.DrawingArea()
        self.drawing.set_size_request(BAR_WIDTH, BAR_HEIGHT * 2 + BAR_GAP + 8)
        self.drawing.connect("draw", self.on_draw)

        self.ebox = Gtk.EventBox()
        self.ebox.add(self.drawing)
        self.ebox.connect("button-press-event", self.on_button_press)
        # Tooltip on the event box (covers the whole applet hit area).
        self.ebox.set_tooltip_text(_("ClaudeBar"))

        self.applet.add(self.ebox)
        self.applet.show_all()

        # Prime and start polling.
        self.refresh()
        self.poll_id = GLib.timeout_add_seconds(max(120, self.poll_interval), self.refresh)

    def refresh(self):
        try:
            out = subprocess.run(
                [self.helper_path, "status"],
                capture_output=True, text=True, timeout=20, check=False,
            )
            if out.returncode != 0:
                self.status = "offline"
                self.snapshot = None
            else:
                data = json.loads(out.stdout)
                self.snapshot = data
                self.status = data.get("status", "ok")
        except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError):
            self.snapshot = None
            self.status = "offline"
        self.drawing.queue_draw()
        self._update_tooltip()
        return True  # keep timer alive

    def _update_tooltip(self):
        """Refresh the panel tooltip with the latest session/weekly percentages."""
        if not self.snapshot:
            # Pick the most informative status string we have.
            if self.status == "rate_limited":
                self.ebox.set_tooltip_text(_("Rate limited by Claude API"))
            elif self.status == "unauthenticated":
                self.ebox.set_tooltip_text(
                    _("Not signed in — open Settings to add a token")
                )
            else:
                self.ebox.set_tooltip_text(
                    _("Offline — last value may be stale")
                )
            return
        session = int(self.snapshot.get("session", {}).get("percent", 0) or 0)
        weekly = int(self.snapshot.get("weekly", {}).get("percent", 0) or 0)
        # Tooltip is multi-line: brand on top, then both percentages.
        self.ebox.set_tooltip_text(
            _("ClaudeBar\nSession: %d%%\nWeekly: %d%%") % (session, weekly)
        )

    def on_draw(self, widget, cr):
        alloc = widget.get_allocation()
        total_h = BAR_HEIGHT * 2 + BAR_GAP
        y_top = (alloc.height - total_h) / 2.0
        y_bot = y_top + BAR_HEIGHT + BAR_GAP

        session = self.snapshot["session"]["percent"] if self.snapshot else 0
        weekly = self.snapshot["weekly"]["percent"] if self.snapshot else 0

        self.draw_bar(cr, 0, y_top, alloc.width, BAR_HEIGHT, session)
        self.draw_bar(cr, 0, y_bot, alloc.width, BAR_HEIGHT, weekly)
        return False

    def draw_bar(self, cr, x, y, w, h, percent):
        r = h / 2.0
        self._rounded(cr, x, y, w, h, r)
        # Theme-aware empty-bar fill: hardcoded white@22% was invisible against
        # light panel themes. Sample the GTK foreground color (which the theme
        # already guarantees contrasts with the panel background) and render
        # the empty track at low alpha so it reads on both light and dark.
        bg_r, bg_g, bg_b, bg_a = self._theme_track_rgba()
        cr.set_source_rgba(bg_r, bg_g, bg_b, bg_a)
        cr.fill()

        p = max(0, min(100, percent))
        if p <= 0:
            return
        fw = max(h, w * p / 100.0)
        rc, gc, bc = self.color_for(p)
        cr.set_source_rgba(rc, gc, bc, 1)
        self._rounded(cr, x, y, fw, h, r)
        cr.fill()

    def _rounded(self, cr, x, y, w, h, r):
        if w < 2 * r:
            r = w / 2
        if h < 2 * r:
            r = h / 2
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 1.5 * math.pi)
        cr.close_path()

    def _theme_track_rgba(self):
        """Empty-bar track color sampled from the GTK theme.

        Reads the widget's foreground color and returns it at 18% alpha so the
        empty portion of each bar is always visible — dark fg on light themes,
        light fg on dark themes. Falls back to mid-grey if style context lookup
        raises (defensive — Gtk.StyleContext.get_color is stable in GTK3 but a
        broken theme could still throw).
        """
        try:
            ctx = self.drawing.get_style_context()
            fg = ctx.get_color(ctx.get_state())
            return (fg.red, fg.green, fg.blue, 0.18)
        except Exception:
            return (0.5, 0.5, 0.5, 0.30)

    def color_for(self, percent):
        if self.status != "ok":
            return (0.55, 0.55, 0.55)
        if percent >= self.crit:
            return (0.93, 0.27, 0.27)
        if percent >= self.warn:
            return (0.96, 0.62, 0.25)
        return (0.26, 0.73, 0.38)

    def on_button_press(self, _widget, event):
        if event.button not in (1, 3):
            return False
        menu = Gtk.Menu()

        refresh = Gtk.MenuItem(label=_("Refresh now"))
        refresh.connect("activate", lambda _i: self.refresh())
        menu.append(refresh)

        menu.append(Gtk.SeparatorMenuItem())

        # Show exactly one of Sign in / Sign out based on current auth state.
        if self.status == "unauthenticated":
            signin = Gtk.MenuItem(label=_("Sign in with Claude"))
            signin.connect("activate", lambda _i: self._start_signin())
            menu.append(signin)
        else:
            signout = Gtk.MenuItem(label=_("Sign out"))
            signout.connect("activate", lambda _i: (self._spawn(["signout"]), self.refresh()))
            menu.append(signout)

        menu.append(Gtk.SeparatorMenuItem())

        open_u = Gtk.MenuItem(label=_("Open claude.ai/settings/usage"))
        open_u.connect("activate", lambda _i: Gio.AppInfo.launch_default_for_uri(
            "https://claude.ai/settings/usage", None))
        menu.append(open_u)

        menu.append(Gtk.SeparatorMenuItem())

        prefs = Gtk.MenuItem(label=_("Preferences"))
        prefs.connect("activate", lambda _i: self._show_preferences())
        menu.append(prefs)

        menu.show_all()
        menu.popup_at_pointer(event)
        return True

    def _show_preferences(self):
        """Modal Preferences dialog — poll interval, warn/crit thresholds, and
        an optional override for the helper binary path. Conventions follow
        other MATE applets (clock, multiload, sticky-notes): right-click ->
        Preferences -> a small Gtk.Dialog with labeled SpinButtons and an
        explicit Apply/Close pair. Values persist to
        ~/.config/claudebar/mate.json and take effect immediately (no
        applet restart needed).
        """
        dlg = Gtk.Dialog(
            title=_("ClaudeBar Preferences"),
            transient_for=None,
            flags=Gtk.DialogFlags.MODAL,
        )
        dlg.add_button(_("Close"), Gtk.ResponseType.CLOSE)
        dlg.add_button(_("Apply"), Gtk.ResponseType.APPLY)
        dlg.set_default_size(380, -1)

        grid = Gtk.Grid(column_spacing=12, row_spacing=8, margin=12)

        # Poll interval (seconds). Match the helper's own clamp range.
        poll_lbl = Gtk.Label(label=_("Poll interval (seconds):"), xalign=0)
        poll_spin = Gtk.SpinButton.new_with_range(120, 3600, 30)
        poll_spin.set_value(self.poll_interval)
        grid.attach(poll_lbl, 0, 0, 1, 1)
        grid.attach(poll_spin, 1, 0, 1, 1)

        # Warn threshold (%). 0 disables; 100 means never.
        warn_lbl = Gtk.Label(label=_("Warn threshold (%):"), xalign=0)
        warn_spin = Gtk.SpinButton.new_with_range(0, 100, 1)
        warn_spin.set_value(self.warn)
        grid.attach(warn_lbl, 0, 1, 1, 1)
        grid.attach(warn_spin, 1, 1, 1, 1)

        # Critical threshold (%).
        crit_lbl = Gtk.Label(label=_("Critical threshold (%):"), xalign=0)
        crit_spin = Gtk.SpinButton.new_with_range(0, 100, 1)
        crit_spin.set_value(self.crit)
        grid.attach(crit_lbl, 0, 2, 1, 1)
        grid.attach(crit_spin, 1, 2, 1, 1)

        # Helper path override. Empty value re-runs the auto-discovery probe.
        helper_lbl = Gtk.Label(label=_("Helper path (blank for auto):"), xalign=0)
        helper_entry = Gtk.Entry()
        helper_entry.set_placeholder_text("/usr/local/bin/claudebar-helper")
        helper_entry.set_text(self.helper_path or "")
        helper_entry.set_hexpand(True)
        grid.attach(helper_lbl, 0, 3, 1, 1)
        grid.attach(helper_entry, 1, 3, 1, 1)

        dlg.get_content_area().add(grid)
        dlg.show_all()

        while True:
            response = dlg.run()
            if response == Gtk.ResponseType.APPLY:
                # Enforce warn <= crit; if the user inverted them, swap.
                w = int(warn_spin.get_value())
                c = int(crit_spin.get_value())
                if w > c:
                    w, c = c, w
                    warn_spin.set_value(w)
                    crit_spin.set_value(c)
                self.poll_interval = int(poll_spin.get_value())
                self.warn = w
                self.crit = c
                hp_text = helper_entry.get_text().strip()
                self.helper_path = hp_text if hp_text else _resolve_helper()
                _save_config({
                    "poll_interval": self.poll_interval,
                    "warn": self.warn,
                    "crit": self.crit,
                    "helper_path": hp_text,
                })
                # Restart the poll timer with the new interval.
                if getattr(self, "poll_id", None):
                    GLib.source_remove(self.poll_id)
                self.poll_id = GLib.timeout_add_seconds(
                    max(120, self.poll_interval), self.refresh
                )
                self.refresh()
                continue
            break
        dlg.destroy()

    def _start_signin(self):
        """Launch `claudebar-helper signin` and poll status until the helper
        reports an authenticated session. Sign-in is an interactive browser
        flow that can take any amount of time, so we can't block; instead we
        re-poll every 3 seconds for up to 60 seconds. Without this, the
        applet sat stale on its old `unauthenticated` snapshot until the
        next regular poll cycle (default 5 minutes) and users had to
        manually click Refresh — confusing UX immediately after a sign-in.
        """
        self._spawn(["signin"])
        self._signin_polls_remaining = 20  # 20 × 3s = 60s
        GLib.timeout_add_seconds(3, self._poll_signin)

    def _poll_signin(self):
        if self._signin_polls_remaining <= 0:
            return False
        self._signin_polls_remaining -= 1
        self.refresh()
        # Stop polling as soon as we leave the unauthenticated state.
        if self.status != "unauthenticated":
            return False
        return True

    def _spawn(self, args):
        # FileNotFoundError used to be silently swallowed here, which made every
        # menu item appear broken when claudebar-helper wasn't on $PATH (the
        # common case under DBus session activation — see _resolve_helper).
        # Surface the failure to stderr so it lands in `journalctl --user`,
        # the standard place to look for misbehaving panel applets.
        try:
            subprocess.Popen([self.helper_path, *args])
        except FileNotFoundError:
            sys.stderr.write(
                "claudebar: helper not found at %r — set $CLAUDEBAR_HELPER or "
                "install claudebar-helper into ~/.local/bin, /usr/local/bin, "
                "or /usr/bin\n" % (self.helper_path,)
            )
            sys.stderr.flush()


def applet_factory(applet, iid, _data):
    if iid != "ClaudebarApplet":
        return False
    Claudebar(applet)
    return True


if __name__ == "__main__":
    MatePanelApplet.Applet.factory_main(
        "ClaudebarAppletFactory",
        True,
        MatePanelApplet.Applet.__gtype__,
        applet_factory,
        None,
    )
