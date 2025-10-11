// SPDX-License-Identifier: GPL-3.0-or-later
//
// Budgie panel applet — two bars drawn with Cairo. Shells out to
// `claudebar-helper status` for data and to `claudebar-helper signin`
// / `signout` for auth.

public class ClaudebarApplet : Budgie.Applet {
    private Gtk.EventBox ebox;
    private Gtk.Box hbox;
    private Gtk.DrawingArea drawing;
    private Gtk.Label session_label;
    private Gtk.Label weekly_label;
    private uint poll_id = 0;

    // Snapshot
    private double session_pct = 0;
    private double weekly_pct = 0;
    private string status = "offline";

    // Settings — persisted to ~/.config/claudebar/budgie.ini via GLib.KeyFile.
    private int  poll_interval    = 300;
    private bool show_percentages = true;
    private int  warn             = 60;
    private int  crit             = 85;
    private string helper_path;

    // budgie-panel inherits its environment from the session, which on
    // Ubuntu / Mint usually means $PATH doesn't include $HOME/.local/bin
    // even though the user's interactive shell adds it. The top-level
    // `make install-helper` installs the helper there by default. Probe
    // the obvious fallback locations so a bare Process.spawn_async call
    // can still find claudebar-helper without the user wiring up
    // CLAUDEBAR_HELPER themselves.
    private static string resolve_helper() {
        string? env = Environment.get_variable("CLAUDEBAR_HELPER");
        if (env != null && env != "" && FileUtils.test(env, FileTest.IS_EXECUTABLE)) {
            return env;
        }
        string? path_hit = Environment.find_program_in_path("claudebar-helper");
        if (path_hit != null) return path_hit;
        string[] candidates = {
            Path.build_filename(Environment.get_home_dir(), ".local", "bin", "claudebar-helper"),
            "/usr/local/bin/claudebar-helper",
            "/usr/bin/claudebar-helper",
            "/usr/libexec/claudebar-helper",
        };
        foreach (string c in candidates) {
            if (FileUtils.test(c, FileTest.IS_EXECUTABLE)) return c;
        }
        return "claudebar-helper";
    }

    public ClaudebarApplet(string uuid) {
#if !BUDGIE_2
        // Budgie 1.x: uuid was a construct property of Budgie.Applet.
        // Budgie 2.x dropped it — the panel manages uuid via the plugin
        // factory in ClaudebarPlugin.get_panel_widget().
        Object(uuid: uuid);
#endif

        helper_path = resolve_helper();
        load_settings();

        ebox = new Gtk.EventBox();
        ebox.set_visible_window(false);
        // GTK3 invisible event boxes still need an explicit event mask for
        // button presses to reach connected handlers reliably across
        // GTK / Budgie versions; without this the menu didn't open on
        // Budgie 2.x.
        ebox.add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
        ebox.button_press_event.connect(on_button_press);

        hbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
        ebox.add(hbox);

        drawing = new Gtk.DrawingArea();
        drawing.set_size_request(64, 22);
        drawing.set_valign(Gtk.Align.CENTER);
        drawing.draw.connect(on_draw);
        hbox.pack_start(drawing, false, false, 0);

        var pct_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 1);
        pct_box.set_valign(Gtk.Align.CENTER);
        // Pango markup keeps the small-text styling portable across the Vala
        // pango bindings shipped by different distros (some don't expose
        // Pango.attr_size_new as a free function).
        session_label = new Gtk.Label("");
        weekly_label  = new Gtk.Label("");
        session_label.use_markup = true;
        weekly_label.use_markup  = true;
        session_label.set_halign(Gtk.Align.END);
        weekly_label.set_halign(Gtk.Align.END);
        pct_box.pack_start(session_label, false, false, 0);
        pct_box.pack_start(weekly_label,  false, false, 0);
        hbox.pack_start(pct_box, false, false, 0);

        add(ebox);
        show_all();
        apply_visibility();

        refresh();
        poll_id = Timeout.add_seconds((uint) poll_interval.clamp(120, 3600), () => {
            refresh();
            return true;
        });
    }

    private void apply_visibility() {
        if (session_label != null) session_label.visible = show_percentages;
        if (weekly_label  != null) weekly_label.visible  = show_percentages;
    }

    private void update_labels_and_tooltip() {
        if (ebox == null) return;
        int s = (int) session_pct;
        int w = (int) weekly_pct;
        if (session_label != null) session_label.label = "<small>%d%%</small>".printf(s);
        if (weekly_label  != null) weekly_label.label  = "<small>%d%%</small>".printf(w);
        ebox.set_tooltip_text(_("ClaudeBar\nSession: %d%%\nWeekly: %d%%").printf(s, w));
    }

    private void restart_poll() {
        if (poll_id != 0) {
            Source.remove(poll_id);
            poll_id = 0;
        }
        poll_id = Timeout.add_seconds((uint) poll_interval.clamp(120, 3600), () => {
            refresh();
            return true;
        });
    }

    public override void panel_position_changed(Budgie.PanelPosition position) {
        // Bars are orientation-agnostic (always horizontal inside their box).
    }

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
        update_labels_and_tooltip();
    }

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

    // Empty-bar track color sampled from the GTK theme. Hardcoded white@22%
    // was invisible against light panel themes; the foreground color is
    // theme-guaranteed to contrast with the panel background, so we use it at
    // 18% alpha for the empty-track look.
    private void theme_track_rgba(out double r, out double g, out double b, out double a) {
        var ctx = drawing.get_style_context();
        Gdk.RGBA fg = ctx.get_color(ctx.get_state());
        r = fg.red;
        g = fg.green;
        b = fg.blue;
        a = 0.18;
    }

    private void draw_bar(Cairo.Context cr, double x, double y, double w, double h, double percent) {
        double r = h / 2.0;
        rounded_rect(cr, x, y, w, h, r);
        double tr, tg, tb, ta;
        theme_track_rgba(out tr, out tg, out tb, out ta);
        cr.set_source_rgba(tr, tg, tb, ta);
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

    private string status_text() {
        switch (status) {
            case "offline":         return _("Offline — last value may be stale");
            case "rate-limited":    return _("Rate limited by Claude API");
            case "unauthenticated": return _("Not signed in — open Settings to add a token");
            default:                return "";
        }
    }

    private bool on_button_press(Gdk.EventButton e) {
        if (e.type != Gdk.EventType.BUTTON_PRESS) return false;
        var menu = new Gtk.Menu();

        int s = (int) session_pct;
        int w = (int) weekly_pct;
        var session_item = new Gtk.MenuItem.with_label(_("Current session: %d%%").printf(s));
        var weekly_item  = new Gtk.MenuItem.with_label(_("Weekly (all models): %d%%").printf(w));
        session_item.sensitive = false;
        weekly_item.sensitive  = false;
        menu.add(session_item);
        menu.add(weekly_item);

        if (status != "ok") {
            var st = status_text();
            if (st != "") {
                var status_item = new Gtk.MenuItem.with_label(st);
                status_item.sensitive = false;
                menu.add(status_item);
            }
        }

        menu.add(new Gtk.SeparatorMenuItem());
        add_item(menu, _("Refresh now"), () => refresh());
        menu.add(new Gtk.SeparatorMenuItem());
        // Show exactly one of Sign in / Sign out based on the current snapshot.
        // Append "…" outside the translated string so translators don't need to repeat it.
        if (status == "unauthenticated") {
            add_item(menu, _("Sign in with Claude") + "…", () => start_signin());
        } else {
            add_item(menu, _("Sign out"), () => { spawn_helper("signout"); refresh(); });
        }
        menu.add(new Gtk.SeparatorMenuItem());
        add_item(menu, _("Open claude.ai/settings/usage"), () => {
            try {
                AppInfo.launch_default_for_uri("https://claude.ai/settings/usage", null);
            } catch (Error e) {}
        });
        menu.add(new Gtk.SeparatorMenuItem());
        add_item(menu, _("Configure") + "…", () => show_configure_dialog());

        menu.show_all();
        menu.popup_at_pointer(e);
        return true;
    }

    private void show_configure_dialog() {
        var dlg = new Gtk.Dialog.with_buttons(
            _("ClaudeBar — Preferences"), null,
            Gtk.DialogFlags.DESTROY_WITH_PARENT,
            _("_Close"), Gtk.ResponseType.CLOSE);
        dlg.set_icon_name("claudebar");
        var content = dlg.get_content_area();
        content.add(build_settings_widget());
        dlg.show_all();
        dlg.response.connect((id) => dlg.destroy());
    }

    private void add_item(Gtk.Menu menu, string label, owned VoidCallback cb) {
        var it = new Gtk.MenuItem.with_label(label);
        it.activate.connect(() => cb());
        menu.add(it);
    }

    private string settings_path() {
        return Path.build_filename(Environment.get_user_config_dir(),
                                   "claudebar", "budgie.ini");
    }

    private void load_settings() {
        var kf = new KeyFile();
        try {
            kf.load_from_file(settings_path(), KeyFileFlags.NONE);
            poll_interval    = kf.get_integer("general", "poll_interval");
            show_percentages = kf.get_boolean("general", "show_percentages");
            warn             = kf.get_integer("general", "warn");
            crit             = kf.get_integer("general", "crit");
        } catch (Error e) {
            // First run or unreadable — keep defaults.
        }
    }

    private void save_settings() {
        var kf = new KeyFile();
        kf.set_integer("general", "poll_interval",    poll_interval);
        kf.set_boolean("general", "show_percentages", show_percentages);
        kf.set_integer("general", "warn",             warn);
        kf.set_integer("general", "crit",             crit);
        try {
            DirUtils.create_with_parents(
                Path.get_dirname(settings_path()), 0700);
            kf.save_to_file(settings_path());
        } catch (Error e) {
            warning("claudebar: save_settings failed: %s", e.message);
        }
    }

    public override bool supports_settings() {
        return true;
    }

    public override Gtk.Widget? get_settings_ui() {
        return build_settings_widget();
    }

    private Gtk.Widget build_settings_widget() {
        var grid = new Gtk.Grid();
        grid.row_spacing = 8;
        grid.column_spacing = 12;
        grid.margin = 12;
        int row = 0;

        // Account
        var signin_btn  = new Gtk.Button.with_label(_("Sign in with Claude"));
        var signout_btn = new Gtk.Button.with_label(_("Sign out"));
        signin_btn.clicked.connect(() => start_signin());
        signout_btn.clicked.connect(() => { spawn_helper("signout"); refresh(); });
        var acc_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        acc_box.pack_start(signin_btn,  false, false, 0);
        acc_box.pack_start(signout_btn, false, false, 0);
        // Hide the irrelevant one based on the current snapshot. show_all on the
        // surrounding dialog won't un-hide it because we also flip no_show_all.
        bool unauth = (status == "unauthenticated");
        var hide_btn = unauth ? signout_btn : signin_btn;
        hide_btn.no_show_all = true;
        hide_btn.visible = false;
        grid.attach(new Gtk.Label(_("Account")), 0, row, 1, 1);
        grid.attach(acc_box,                      1, row, 1, 1); row++;

        // Poll interval
        var poll_spin = new Gtk.SpinButton.with_range(120, 3600, 30);
        poll_spin.value = poll_interval;
        poll_spin.value_changed.connect(() => {
            poll_interval = (int) poll_spin.value;
            save_settings();
            restart_poll();
        });
        grid.attach(new Gtk.Label(_("Poll interval (seconds)")), 0, row, 1, 1);
        grid.attach(poll_spin,                                    1, row, 1, 1); row++;

        // Show percentages
        var show_chk = new Gtk.CheckButton.with_label(_("Show numeric percentages next to bars"));
        show_chk.active = show_percentages;
        show_chk.toggled.connect(() => {
            show_percentages = show_chk.active;
            save_settings();
            apply_visibility();
        });
        grid.attach(show_chk, 0, row, 2, 1); row++;

        // Warn / Crit thresholds
        var warn_spin = new Gtk.SpinButton.with_range(0, 100, 5);
        warn_spin.value = warn;
        warn_spin.value_changed.connect(() => {
            warn = (int) warn_spin.value;
            save_settings();
            drawing.queue_draw();
        });
        var crit_spin = new Gtk.SpinButton.with_range(0, 100, 5);
        crit_spin.value = crit;
        crit_spin.value_changed.connect(() => {
            crit = (int) crit_spin.value;
            save_settings();
            drawing.queue_draw();
        });
        grid.attach(new Gtk.Label(_("Orange at (%)")), 0, row, 1, 1);
        grid.attach(warn_spin,                          1, row, 1, 1); row++;
        grid.attach(new Gtk.Label(_("Red at (%)")),    0, row, 1, 1);
        grid.attach(crit_spin,                          1, row, 1, 1); row++;

        grid.show_all();
        return grid;
    }

    private void spawn_helper(string subcmd) {
        try {
            Pid pid;
            Process.spawn_async(null, { helper_path, subcmd, null }, null,
                                SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                                null, out pid);
            ChildWatch.add(pid, (_pid, _status) => Process.close_pid(pid));
        } catch (Error e) {
            warning("claudebar: %s spawn failed: %s", subcmd, e.message);
        }
    }

    // Launch signin and poll status until the user finishes the OAuth flow
    // in their browser. Without the short-cadence poll, the bars stayed on
    // their stale `unauthenticated` snapshot until the next regular poll
    // (default 5 minutes) and users had to manually click Refresh.
    private int signin_polls_remaining = 0;
    private void start_signin() {
        spawn_helper("signin");
        signin_polls_remaining = 20;  // 20 × 3s = 60s
        Timeout.add_seconds(3, () => {
            if (signin_polls_remaining <= 0) return false;
            signin_polls_remaining--;
            refresh();
            return status == "unauthenticated";
        });
    }

    private delegate void VoidCallback();
}
