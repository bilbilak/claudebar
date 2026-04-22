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
import json
import math
import os
import subprocess

DEFAULT_INTERVAL = 300
DEFAULT_WARN = 60
DEFAULT_CRIT = 85
BAR_WIDTH = 64
BAR_HEIGHT = 6
BAR_GAP = 4


class Claudebar:
    def __init__(self, applet):
        self.applet = applet
        self.poll_interval = DEFAULT_INTERVAL
        self.warn = DEFAULT_WARN
        self.crit = DEFAULT_CRIT
        self.helper_path = os.environ.get("CLAUDEBAR_HELPER", "claudebar-helper")
        self.snapshot = None
        self.status = "offline"

        self.drawing = Gtk.DrawingArea()
        self.drawing.set_size_request(BAR_WIDTH, BAR_HEIGHT * 2 + BAR_GAP + 8)
        self.drawing.connect("draw", self.on_draw)

        self.ebox = Gtk.EventBox()
        self.ebox.add(self.drawing)
        self.ebox.add_events(Gtk.gdk.EventMask.BUTTON_PRESS_MASK if hasattr(Gtk, "gdk") else 0)
        self.ebox.connect("button-press-event", self.on_button_press)

        self.applet.add(self.ebox)
        self.applet.show_all()

        # Prime and start polling.
        self.refresh()
        self.poll_id = GLib.timeout_add_seconds(max(60, self.poll_interval), self.refresh)

    # ------------- Data fetch -------------

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
        return True  # keep timer alive

    # ------------- Drawing -------------

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
        cr.set_source_rgba(1, 1, 1, 0.22)
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

    def color_for(self, percent):
        if self.status != "ok":
            return (0.55, 0.55, 0.55)
        if percent >= self.crit:
            return (0.93, 0.27, 0.27)
        if percent >= self.warn:
            return (0.96, 0.62, 0.25)
        return (0.26, 0.73, 0.38)

    # ------------- Menu -------------

    def on_button_press(self, _widget, event):
        if event.button not in (1, 3):
            return False
        menu = Gtk.Menu()

        refresh = Gtk.MenuItem(label="Refresh now")
        refresh.connect("activate", lambda _i: self.refresh())
        menu.append(refresh)

        menu.append(Gtk.SeparatorMenuItem())

        signin = Gtk.MenuItem(label="Sign in with Claude…")
        signin.connect("activate", lambda _i: self._spawn(["signin"]))
        menu.append(signin)

        signout = Gtk.MenuItem(label="Sign out")
        signout.connect("activate", lambda _i: (self._spawn(["signout"]), self.refresh()))
        menu.append(signout)

        menu.append(Gtk.SeparatorMenuItem())

        open_u = Gtk.MenuItem(label="Open claude.ai/settings/usage")
        open_u.connect("activate", lambda _i: Gio.AppInfo.launch_default_for_uri(
            "https://claude.ai/settings/usage", None))
        menu.append(open_u)

        menu.show_all()
        menu.popup_at_pointer(event)
        return True

    def _spawn(self, args):
        try:
            subprocess.Popen([self.helper_path, *args])
        except FileNotFoundError:
            pass


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
