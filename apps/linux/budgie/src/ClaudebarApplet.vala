// SPDX-License-Identifier: GPL-3.0-or-later
//
// Budgie panel applet — two bars drawn with Cairo. Shells out to
// `claudebar-helper status` for data and to `claudebar-helper signin`
// / `signout` for auth.

public class ClaudebarApplet : Budgie.Applet {
    private Gtk.EventBox ebox;
    private Gtk.DrawingArea drawing;
    private uint poll_id = 0;

    // Snapshot
    private double session_pct = 0;
    private double weekly_pct = 0;
    private string status = "offline";

    // Settings (hard-coded for v0.1; wire to GSettings later).
    private int poll_interval = 300;
    private int warn = 60;
    private int crit = 85;
    private string helper_path = "claudebar-helper";

    public ClaudebarApplet(string uuid) {
        Object(uuid: uuid);

        ebox = new Gtk.EventBox();
        ebox.set_visible_window(false);
        drawing = new Gtk.DrawingArea();
        drawing.set_size_request(64, 22);
        drawing.draw.connect(on_draw);
        ebox.add(drawing);
        ebox.button_press_event.connect(on_button_press);

        add(ebox);
        show_all();

        refresh();
        poll_id = Timeout.add_seconds((uint) poll_interval.clamp(60, 3600), () => {
            refresh();
            return true;
        });
    }

    public override void panel_position_changed(Budgie.PanelPosition position) {
        // Bars are orientation-agnostic (always horizontal inside their box).
    }

    // --- Data fetch -------------------------------------------------------

    private void refresh() {
        try {
            string stdout_buf;
            int exit_status;
            Process.spawn_sync(
                null,
                { helper_path, "status", null },
                null,
                SpawnFlags.SEARCH_PATH,
                null,
                out stdout_buf,
                null,
                out exit_status
            );
            if (exit_status != 0 || stdout_buf == null || stdout_buf.length == 0) {
                session_pct = 0;
                weekly_pct = 0;
                status = "offline";
                drawing.queue_draw();
                return;
            }
            var parser = new Json.Parser();
            parser.load_from_data(stdout_buf);
            var obj = parser.get_root().get_object();
            status = obj.get_string_member_with_default("status", "offline");
            if (obj.has_member("session")) {
                var b = obj.get_object_member("session");
                session_pct = b.get_double_member_with_default("percent", 0);
            }
            if (obj.has_member("weekly")) {
                var b = obj.get_object_member("weekly");
                weekly_pct = b.get_double_member_with_default("percent", 0);
            }
        } catch (Error e) {
            status = "offline";
            session_pct = 0;
            weekly_pct = 0;
        }
        drawing.queue_draw();
    }

    // --- Drawing ----------------------------------------------------------

    private const double BAR_HEIGHT = 6.0;
    private const double BAR_GAP = 4.0;

    private bool on_draw(Cairo.Context cr) {
        int w = drawing.get_allocated_width();
        int h = drawing.get_allocated_height();
        double total = BAR_HEIGHT * 2 + BAR_GAP;
        double y_top = (h - total) / 2.0;
        double y_bot = y_top + BAR_HEIGHT + BAR_GAP;

        draw_bar(cr, 0, y_top, w, BAR_HEIGHT, session_pct);
        draw_bar(cr, 0, y_bot, w, BAR_HEIGHT, weekly_pct);
        return true;
    }

    private void draw_bar(Cairo.Context cr, double x, double y, double w, double h, double percent) {
        double r = h / 2.0;
        rounded_rect(cr, x, y, w, h, r);
        cr.set_source_rgba(1, 1, 1, 0.22);
        cr.fill();

        double p = percent.clamp(0, 100);
        if (p <= 0) return;
        double fw = double.max(h, w * p / 100.0);
        double[] rgba = color_for(p);
        cr.set_source_rgba(rgba[0], rgba[1], rgba[2], rgba[3]);
        rounded_rect(cr, x, y, fw, h, r);
        cr.fill();
    }

    private void rounded_rect(Cairo.Context cr, double x, double y, double w, double h, double r) {
        if (w < 2 * r) r = w / 2;
        if (h < 2 * r) r = h / 2;
        cr.new_sub_path();
        cr.arc(x + w - r, y + r,     r, -Math.PI / 2, 0);
        cr.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
        cr.arc(x + r,     y + h - r, r, Math.PI / 2, Math.PI);
        cr.arc(x + r,     y + r,     r, Math.PI, 1.5 * Math.PI);
        cr.close_path();
    }

    private double[] color_for(double percent) {
        if (status != "ok") return { 0.55, 0.55, 0.55, 1.0 };
        if (percent >= crit) return { 0.93, 0.27, 0.27, 1.0 };
        if (percent >= warn) return { 0.96, 0.62, 0.25, 1.0 };
        return { 0.26, 0.73, 0.38, 1.0 };
    }

    // --- Menu -------------------------------------------------------------

    private bool on_button_press(Gdk.EventButton e) {
        if (e.type != Gdk.EventType.BUTTON_PRESS) return false;
        var menu = new Gtk.Menu();

        add_item(menu, "Refresh now", () => refresh());
        menu.add(new Gtk.SeparatorMenuItem());
        add_item(menu, "Sign in with Claude…", () => spawn_helper("signin"));
        add_item(menu, "Sign out", () => { spawn_helper("signout"); refresh(); });
        menu.add(new Gtk.SeparatorMenuItem());
        add_item(menu, "Open claude.ai/settings/usage", () => {
            try {
                AppInfo.launch_default_for_uri("https://claude.ai/settings/usage", null);
            } catch (Error e) {}
        });

        menu.show_all();
        menu.popup_at_pointer(e);
        return true;
    }

    private void add_item(Gtk.Menu menu, string label, owned VoidCallback cb) {
        var it = new Gtk.MenuItem.with_label(label);
        it.activate.connect(() => cb());
        menu.add(it);
    }

    private void spawn_helper(string subcmd) {
        try {
            Pid pid;
            Process.spawn_async(null, { helper_path, subcmd, null }, null,
                                SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                                null, out pid);
            ChildWatch.add(pid, (_pid, _status) => Process.close_pid(pid));
        } catch (Error e) {}
    }

    private delegate void VoidCallback();
}
