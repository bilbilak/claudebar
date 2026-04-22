// SPDX-License-Identifier: GPL-3.0-or-later
// Cinnamon applet: two-bar Claude.ai usage indicator in the panel.

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Mainloop = imports.mainloop;
const Lang = imports.lang;
const St = imports.gi.St;
const Clutter = imports.gi.Clutter;
const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;
const cairo = imports.cairo;
const Settings = imports.ui.settings;

const UUID = "claudebar@bilbilak.org";
const AppletDir = imports.ui.appletManager.applets[UUID];
const Api = AppletDir.api;
const Auth = AppletDir.auth;
const OAuth = AppletDir.oauth;

const BAR_WIDTH = 64;
const BAR_HEIGHT = 6;
const BAR_GAP = 4;

function ClaudebarApplet(metadata, orientation, panelHeight, instance_id) {
    this._init(metadata, orientation, panelHeight, instance_id);
}

ClaudebarApplet.prototype = {
    __proto__: Applet.Applet.prototype,

    _init: function(metadata, orientation, panelHeight, instance_id) {
        Applet.Applet.prototype._init.call(this, orientation, panelHeight, instance_id);

        this._source = new Api.ClaudeBarSource();
        this._snapshot = null;
        this._pollId = 0;

        // --- Settings ---
        this.settings = new Settings.AppletSettings(this, UUID, instance_id);
        this.settings.bind("poll-interval-seconds", "pollInterval", () => this._restartPolling());
        this.settings.bind("show-percentages", "showPercentages", () => this._redraw());
        this.settings.bind("warn-threshold", "warnThreshold", () => this._redraw());
        this.settings.bind("critical-threshold", "criticalThreshold", () => this._redraw());
        this.settings.connect("sign-in", Lang.bind(this, this.onSignInClicked));
        this.settings.connect("sign-out", Lang.bind(this, this.onSignOutClicked));

        // --- Panel area: the bars ---
        this._area = new St.DrawingArea({
            width: BAR_WIDTH,
            height: BAR_HEIGHT * 2 + BAR_GAP,
            y_align: Clutter.ActorAlign.CENTER,
            style_class: "claudebar-bars",
        });
        this._area.connect("repaint", (a) => this._draw(a));

        // Replace default icon with our drawing area.
        this.actor.add_style_class_name("claudebar-applet");
        this.actor.remove_all_children && this.actor.remove_all_children();
        this.actor.add(this._area, { y_align: St.Align.MIDDLE });

        // --- Popup menu ---
        this.menuManager = new PopupMenu.PopupMenuManager(this);
        this.menu = new Applet.AppletPopupMenu(this, orientation);
        this.menuManager.addMenu(this.menu);
        this._buildMenu();

        // --- Poll loop ---
        this._startPolling();
        this._refresh();
    },

    on_applet_clicked: function() {
        this.menu.toggle();
    },

    _buildMenu: function() {
        this._sessionItem = new PopupMenu.PopupMenuItem("Current session: —", { reactive: false });
        this.menu.addMenuItem(this._sessionItem);
        this._sessionReset = new PopupMenu.PopupMenuItem("", { reactive: false });
        this._sessionReset.label.style_class = "claudebar-submenu";
        this.menu.addMenuItem(this._sessionReset);

        this._weeklyItem = new PopupMenu.PopupMenuItem("Weekly (all models): —", { reactive: false });
        this.menu.addMenuItem(this._weeklyItem);
        this._weeklyReset = new PopupMenu.PopupMenuItem("", { reactive: false });
        this._weeklyReset.label.style_class = "claudebar-submenu";
        this.menu.addMenuItem(this._weeklyReset);

        this._statusLine = new PopupMenu.PopupMenuItem("", { reactive: false });
        this._statusLine.actor.hide();
        this.menu.addMenuItem(this._statusLine);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const refresh = new PopupMenu.PopupMenuItem("Refresh now");
        refresh.connect("activate", Lang.bind(this, this._refresh));
        this.menu.addMenuItem(refresh);

        const open = new PopupMenu.PopupMenuItem("Open claude.ai/settings/usage");
        open.connect("activate", () => {
            Gio.AppInfo.launch_default_for_uri("https://claude.ai/settings/usage", null);
        });
        this.menu.addMenuItem(open);
    },

    _startPolling: function() {
        if (this._pollId) return;
        const interval = Math.max(60, this.pollInterval || 300);
        this._pollId = Mainloop.timeout_add_seconds(interval, Lang.bind(this, () => {
            this._refresh();
            return true;
        }));
    },

    _restartPolling: function() {
        if (this._pollId) {
            Mainloop.source_remove(this._pollId);
            this._pollId = 0;
        }
        this._startPolling();
    },

    _refresh: function() {
        this._source.fetch().then((snap) => {
            this._snapshot = snap;
            this._redraw();
            this._updateMenu();
        }).catch((e) => {
            global.logError("claudebar: refresh failed: " + e);
            this._snapshot = {
                session: { percent: 0, resetsAt: null },
                weekly: { percent: 0, resetsAt: null },
                status: "offline",
                fetchedAt: new Date(),
            };
            this._redraw();
            this._updateMenu();
        });
    },

    _redraw: function() {
        if (this._area) this._area.queue_repaint();
    },

    _updateMenu: function() {
        const s = this._snapshot;
        if (!s) return;
        this._sessionItem.label.text = `Current session: ${s.session.percent.toFixed(0)}%`;
        this._sessionReset.label.text = `Resets ${formatReset(s.session.resetsAt)}`;
        this._weeklyItem.label.text = `Weekly (all models): ${s.weekly.percent.toFixed(0)}%`;
        this._weeklyReset.label.text = `Resets ${formatReset(s.weekly.resetsAt)}`;

        const statusTexts = {
            ok: "",
            offline: "Offline — last value may be stale",
            "rate-limited": "Rate limited by Claude API",
            unauthenticated: "Not signed in — open Settings to add a token",
        };
        const text = statusTexts[s.status] || "";
        this._statusLine.label.text = text;
        if (text) this._statusLine.actor.show();
        else this._statusLine.actor.hide();
    },

    _draw: function(area) {
        const [w, h] = area.get_surface_size();
        const cr = area.get_context();
        cr.setOperator(cairo.Operator.CLEAR);
        cr.paint();
        cr.setOperator(cairo.Operator.OVER);

        const warn = this.warnThreshold || 60;
        const crit = this.criticalThreshold || 85;
        const snap = this._snapshot;
        const status = snap ? snap.status : "offline";
        const sessPct = snap ? snap.session.percent : 0;
        const weekPct = snap ? snap.weekly.percent : 0;

        drawBar(cr, 0, 0, w, BAR_HEIGHT, sessPct, status, warn, crit);
        drawBar(cr, 0, BAR_HEIGHT + BAR_GAP, w, BAR_HEIGHT, weekPct, status, warn, crit);

        cr.$dispose();
    },

    // --- Settings button callbacks ---

    onSignInClicked: function() {
        try {
            const flow = OAuth.startLoginFlow();
            Gio.AppInfo.launch_default_for_uri(flow.authorizeUrl, null);
            flow.result
                .then((tokens) => Auth.storeTokens(tokens))
                .then(() => this._refresh())
                .catch((e) => global.logError("claudebar: sign-in failed: " + e));
        } catch (e) {
            global.logError("claudebar: startLoginFlow failed: " + e);
        }
    },

    onSignOutClicked: function() {
        Auth.clearTokens()
            .then(() => this._refresh())
            .catch((e) => global.logError("claudebar: clearTokens failed: " + e));
    },

    on_applet_removed_from_panel: function() {
        if (this._pollId) {
            Mainloop.source_remove(this._pollId);
            this._pollId = 0;
        }
        if (this.settings) {
            this.settings.finalize();
            this.settings = null;
        }
    },
};

// --- Drawing helpers ---

function drawBar(cr, x, y, w, h, percent, status, warn, crit) {
    const r = h / 2;
    roundedRect(cr, x, y, w, h, r);
    cr.setSourceRGBA(0.55, 0.55, 0.55, 0.22);
    cr.fill();
    const p = Math.max(0, Math.min(100, percent));
    if (p <= 0) return;
    const fw = Math.max(h, (w * p) / 100);
    const [rC, gC, bC] = colorFor(p, status, warn, crit);
    cr.setSourceRGBA(rC, gC, bC, 1);
    roundedRect(cr, x, y, fw, h, r);
    cr.fill();
}

function roundedRect(cr, x, y, w, h, r) {
    if (w < 2 * r) r = w / 2;
    if (h < 2 * r) r = h / 2;
    cr.newSubPath();
    cr.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
    cr.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
    cr.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
    cr.arc(x + r, y + r, r, Math.PI, 1.5 * Math.PI);
    cr.closePath();
}

function colorFor(percent, status, warn, crit) {
    if (status !== "ok") return [0.55, 0.55, 0.55];
    if (percent >= crit) return [0.93, 0.27, 0.27];
    if (percent >= warn) return [0.96, 0.62, 0.25];
    return [0.26, 0.73, 0.38];
}

function formatReset(d) {
    if (!d) return "—";
    const ms = d.getTime() - Date.now();
    if (ms <= 0) return "now";
    const mins = Math.round(ms / 60000);
    if (mins < 60) return `in ${mins} min`;
    const hrs = Math.floor(mins / 60);
    const rem = mins % 60;
    if (hrs < 24) return rem ? `in ${hrs}h ${rem}m` : `in ${hrs}h`;
    const days = Math.floor(hrs / 24);
    const remH = hrs % 24;
    return remH ? `in ${days}d ${remH}h` : `in ${days}d`;
}

// --- Entrypoint ---

function main(metadata, orientation, panelHeight, instance_id) {
    return new ClaudebarApplet(metadata, orientation, panelHeight, instance_id);
}
