// SPDX-License-Identifier: GPL-3.0-or-later
// claudebar — XFCE panel plugin.
// Shells out to `claudebar-helper status` every N seconds and paints two bars.

#include <gtk/gtk.h>
#include <libxfce4panel/libxfce4panel.h>
#include <libxfce4util/libxfce4util.h>
#include <json-glib/json-glib.h>
#include <math.h>
#include <string.h>

#define DEFAULT_POLL_INTERVAL 300
#define DEFAULT_WARN          60
#define DEFAULT_CRIT          85
#define BAR_WIDTH             64
#define BAR_HEIGHT            6
#define BAR_GAP               4

typedef enum {
    STATUS_OK,
    STATUS_OFFLINE,
    STATUS_RATE_LIMITED,
    STATUS_UNAUTHENTICATED,
} ClaudeStatus;

typedef struct {
    double session_percent;
    double weekly_percent;
    gint64 session_resets_at_unix;   // 0 if unknown
    gint64 weekly_resets_at_unix;
    ClaudeStatus status;
} Snapshot;

typedef struct {
    XfcePanelPlugin *plugin;
    GtkWidget       *ebox;           // event box for click handling
    GtkWidget       *drawing;        // GtkDrawingArea showing the bars
    Snapshot         snapshot;
    guint            poll_id;
    guint            poll_interval;
    guint            warn_threshold;
    guint            crit_threshold;
    gchar           *helper_path;
    GCancellable    *cancel;
} ClaudebarPlugin;

// ---------------------------------------------------------------------------
// Snapshot helpers
// ---------------------------------------------------------------------------

static void snapshot_reset(Snapshot *s, ClaudeStatus status) {
    s->session_percent = 0;
    s->weekly_percent = 0;
    s->session_resets_at_unix = 0;
    s->weekly_resets_at_unix = 0;
    s->status = status;
}

static ClaudeStatus parse_status(const char *s) {
    if (!s) return STATUS_OFFLINE;
    if (g_str_equal(s, "ok")) return STATUS_OK;
    if (g_str_equal(s, "rate-limited")) return STATUS_RATE_LIMITED;
    if (g_str_equal(s, "unauthenticated")) return STATUS_UNAUTHENTICATED;
    return STATUS_OFFLINE;
}

static gint64 parse_iso8601_unix(const char *iso) {
    if (!iso) return 0;
    GDateTime *dt = g_date_time_new_from_iso8601(iso, NULL);
    if (!dt) return 0;
    gint64 unix_s = g_date_time_to_unix(dt);
    g_date_time_unref(dt);
    return unix_s;
}

static void bucket_from_json(JsonObject *obj, const char *key,
                             double *out_pct, gint64 *out_reset) {
    if (!obj || !json_object_has_member(obj, key)) return;
    JsonNode *node = json_object_get_member(obj, key);
    if (!JSON_NODE_HOLDS_OBJECT(node)) return;
    JsonObject *bucket = json_node_get_object(node);
    if (json_object_has_member(bucket, "percent"))
        *out_pct = json_object_get_double_member(bucket, "percent");
    if (json_object_has_member(bucket, "resets_at")) {
        JsonNode *rn = json_object_get_member(bucket, "resets_at");
        if (JSON_NODE_HOLDS_VALUE(rn)) {
            const char *iso = json_node_get_string(rn);
            *out_reset = parse_iso8601_unix(iso);
        }
    }
}

static gboolean parse_helper_output(const char *text, Snapshot *out) {
    JsonParser *parser = json_parser_new();
    GError *err = NULL;
    if (!json_parser_load_from_data(parser, text, -1, &err)) {
        if (err) { g_warning("claudebar: helper JSON parse failed: %s", err->message); g_error_free(err); }
        g_object_unref(parser);
        return FALSE;
    }
    JsonNode *root = json_parser_get_root(parser);
    if (!root || !JSON_NODE_HOLDS_OBJECT(root)) { g_object_unref(parser); return FALSE; }
    JsonObject *obj = json_node_get_object(root);

    snapshot_reset(out, STATUS_OK);
    if (json_object_has_member(obj, "status")) {
        out->status = parse_status(json_object_get_string_member(obj, "status"));
    }
    bucket_from_json(obj, "session", &out->session_percent, &out->session_resets_at_unix);
    bucket_from_json(obj, "weekly",  &out->weekly_percent,  &out->weekly_resets_at_unix);

    g_object_unref(parser);
    return TRUE;
}

// ---------------------------------------------------------------------------
// Helper invocation
// ---------------------------------------------------------------------------

static gchar *run_helper_sync(const char *helper_path, const char *subcmd) {
    gchar *argv[3] = { (gchar *)helper_path, (gchar *)subcmd, NULL };
    gchar *stdout_buf = NULL;
    gchar *stderr_buf = NULL;
    gint   exit_status = 0;
    GError *err = NULL;
    if (!g_spawn_sync(NULL, argv, NULL,
                      G_SPAWN_SEARCH_PATH,
                      NULL, NULL,
                      &stdout_buf, &stderr_buf,
                      &exit_status, &err)) {
        if (err) { g_warning("claudebar: spawn failed: %s", err->message); g_error_free(err); }
        g_free(stderr_buf);
        return NULL;
    }
    g_free(stderr_buf);
    if (!g_spawn_check_exit_status(exit_status, NULL)) {
        g_free(stdout_buf);
        return NULL;
    }
    return stdout_buf;
}

static void refresh_snapshot(ClaudebarPlugin *cb) {
    gchar *text = run_helper_sync(cb->helper_path, "status");
    if (text) {
        if (!parse_helper_output(text, &cb->snapshot)) {
            snapshot_reset(&cb->snapshot, STATUS_OFFLINE);
        }
        g_free(text);
    } else {
        snapshot_reset(&cb->snapshot, STATUS_OFFLINE);
    }
    if (cb->drawing) gtk_widget_queue_draw(cb->drawing);
}

static gboolean on_poll_tick(gpointer data) {
    refresh_snapshot((ClaudebarPlugin *)data);
    return G_SOURCE_CONTINUE;
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

static void set_color_for(cairo_t *cr, double pct, ClaudeStatus status,
                          guint warn, guint crit) {
    if (status != STATUS_OK) {
        cairo_set_source_rgba(cr, 0.55, 0.55, 0.55, 1.0);
        return;
    }
    if (pct >= (double)crit) {
        cairo_set_source_rgba(cr, 0.93, 0.27, 0.27, 1.0);
        return;
    }
    if (pct >= (double)warn) {
        cairo_set_source_rgba(cr, 0.96, 0.62, 0.25, 1.0);
        return;
    }
    cairo_set_source_rgba(cr, 0.26, 0.73, 0.38, 1.0);
}

static void rounded_rect(cairo_t *cr, double x, double y, double w, double h, double r) {
    if (w < 2 * r) r = w / 2;
    if (h < 2 * r) r = h / 2;
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r,     r, -G_PI_2, 0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0, G_PI_2);
    cairo_arc(cr, x + r,     y + h - r, r, G_PI_2, G_PI);
    cairo_arc(cr, x + r,     y + r,     r, G_PI, 1.5 * G_PI);
    cairo_close_path(cr);
}

static void draw_bar(cairo_t *cr, double x, double y, double w, double h,
                     double percent, ClaudeStatus status, guint warn, guint crit) {
    double r = h / 2.0;
    cairo_set_source_rgba(cr, 1, 1, 1, 0.22);
    rounded_rect(cr, x, y, w, h, r);
    cairo_fill(cr);

    double p = CLAMP(percent, 0, 100);
    if (p <= 0) return;
    double fw = MAX(h, w * p / 100.0);
    set_color_for(cr, p, status, warn, crit);
    rounded_rect(cr, x, y, fw, h, r);
    cairo_fill(cr);
}

static gboolean on_draw(GtkWidget *widget, cairo_t *cr, gpointer data) {
    ClaudebarPlugin *cb = (ClaudebarPlugin *)data;
    GtkAllocation alloc;
    gtk_widget_get_allocation(widget, &alloc);

    double total_h = BAR_HEIGHT * 2 + BAR_GAP;
    double y_top   = (alloc.height - total_h) / 2.0;
    double y_bot   = y_top + BAR_HEIGHT + BAR_GAP;
    double w       = alloc.width;

    draw_bar(cr, 0, y_top, w, BAR_HEIGHT, cb->snapshot.session_percent,
             cb->snapshot.status, cb->warn_threshold, cb->crit_threshold);
    draw_bar(cr, 0, y_bot, w, BAR_HEIGHT, cb->snapshot.weekly_percent,
             cb->snapshot.status, cb->warn_threshold, cb->crit_threshold);
    return FALSE;
}

// ---------------------------------------------------------------------------
// Menu
// ---------------------------------------------------------------------------

static void on_sign_in(GtkMenuItem *m G_GNUC_UNUSED, gpointer data) {
    ClaudebarPlugin *cb = (ClaudebarPlugin *)data;
    gchar *argv[3] = { cb->helper_path, "signin", NULL };
    GError *err = NULL;
    if (!g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH,
                       NULL, NULL, NULL, &err)) {
        if (err) { g_warning("claudebar: signin spawn failed: %s", err->message); g_error_free(err); }
    }
}

static void on_sign_out(GtkMenuItem *m G_GNUC_UNUSED, gpointer data) {
    ClaudebarPlugin *cb = (ClaudebarPlugin *)data;
    gchar *argv[3] = { cb->helper_path, "signout", NULL };
    g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL);
    refresh_snapshot(cb);
}

static void on_refresh(GtkMenuItem *m G_GNUC_UNUSED, gpointer data) {
    refresh_snapshot((ClaudebarPlugin *)data);
}

static void on_open_usage(GtkMenuItem *m G_GNUC_UNUSED, gpointer data G_GNUC_UNUSED) {
    gtk_show_uri_on_window(NULL, "https://claude.ai/settings/usage", GDK_CURRENT_TIME, NULL);
}

static gboolean on_button_press(GtkWidget *w G_GNUC_UNUSED, GdkEventButton *e, gpointer data) {
    if (e->type != GDK_BUTTON_PRESS) return FALSE;
    ClaudebarPlugin *cb = (ClaudebarPlugin *)data;

    GtkWidget *menu = gtk_menu_new();
    GtkWidget *refresh   = gtk_menu_item_new_with_label("Refresh now");
    GtkWidget *sep1      = gtk_separator_menu_item_new();
    GtkWidget *signin    = gtk_menu_item_new_with_label("Sign in with Claude…");
    GtkWidget *signout   = gtk_menu_item_new_with_label("Sign out");
    GtkWidget *sep2      = gtk_separator_menu_item_new();
    GtkWidget *open_u    = gtk_menu_item_new_with_label("Open claude.ai/settings/usage");

    g_signal_connect(refresh, "activate", G_CALLBACK(on_refresh),    cb);
    g_signal_connect(signin,  "activate", G_CALLBACK(on_sign_in),    cb);
    g_signal_connect(signout, "activate", G_CALLBACK(on_sign_out),   cb);
    g_signal_connect(open_u,  "activate", G_CALLBACK(on_open_usage), cb);

    gtk_menu_shell_append(GTK_MENU_SHELL(menu), refresh);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), sep1);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), signin);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), signout);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), sep2);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), open_u);
    gtk_widget_show_all(menu);
    gtk_menu_popup_at_pointer(GTK_MENU(menu), (GdkEvent *)e);
    return TRUE;
}

// ---------------------------------------------------------------------------
// Configuration (rc)
// ---------------------------------------------------------------------------

static void save_config(ClaudebarPlugin *cb) {
    gchar *file = xfce_panel_plugin_save_location(cb->plugin, TRUE);
    if (!file) return;
    XfceRc *rc = xfce_rc_simple_open(file, FALSE);
    g_free(file);
    if (!rc) return;
    xfce_rc_set_group(rc, "general");
    xfce_rc_write_int_entry(rc, "poll_interval", (gint)cb->poll_interval);
    xfce_rc_write_int_entry(rc, "warn",          (gint)cb->warn_threshold);
    xfce_rc_write_int_entry(rc, "crit",          (gint)cb->crit_threshold);
    xfce_rc_write_entry(rc, "helper_path", cb->helper_path ? cb->helper_path : "claudebar-helper");
    xfce_rc_close(rc);
}

static void load_config(ClaudebarPlugin *cb) {
    cb->poll_interval = DEFAULT_POLL_INTERVAL;
    cb->warn_threshold = DEFAULT_WARN;
    cb->crit_threshold = DEFAULT_CRIT;
    cb->helper_path = g_strdup("claudebar-helper");

    gchar *file = xfce_panel_plugin_save_location(cb->plugin, FALSE);
    if (!file) return;
    XfceRc *rc = xfce_rc_simple_open(file, TRUE);
    g_free(file);
    if (!rc) return;
    xfce_rc_set_group(rc, "general");
    cb->poll_interval  = (guint)xfce_rc_read_int_entry(rc, "poll_interval", DEFAULT_POLL_INTERVAL);
    cb->warn_threshold = (guint)xfce_rc_read_int_entry(rc, "warn",          DEFAULT_WARN);
    cb->crit_threshold = (guint)xfce_rc_read_int_entry(rc, "crit",          DEFAULT_CRIT);
    const gchar *hp = xfce_rc_read_entry(rc, "helper_path", "claudebar-helper");
    g_free(cb->helper_path);
    cb->helper_path = g_strdup(hp);
    xfce_rc_close(rc);
}

// ---------------------------------------------------------------------------
// Plugin lifecycle
// ---------------------------------------------------------------------------

static void claudebar_free(XfcePanelPlugin *plugin, ClaudebarPlugin *cb) {
    (void)plugin;
    if (cb->poll_id) { g_source_remove(cb->poll_id); cb->poll_id = 0; }
    save_config(cb);
    g_free(cb->helper_path);
    g_free(cb);
}

static void claudebar_construct(XfcePanelPlugin *plugin) {
    ClaudebarPlugin *cb = g_new0(ClaudebarPlugin, 1);
    cb->plugin = plugin;
    load_config(cb);
    snapshot_reset(&cb->snapshot, STATUS_OFFLINE);

    cb->ebox = gtk_event_box_new();
    gtk_event_box_set_visible_window(GTK_EVENT_BOX(cb->ebox), FALSE);
    gtk_widget_add_events(cb->ebox, GDK_BUTTON_PRESS_MASK);

    cb->drawing = gtk_drawing_area_new();
    gtk_widget_set_size_request(cb->drawing, BAR_WIDTH, BAR_HEIGHT * 2 + BAR_GAP + 8);
    g_signal_connect(cb->drawing, "draw", G_CALLBACK(on_draw), cb);
    gtk_container_add(GTK_CONTAINER(cb->ebox), cb->drawing);

    gtk_container_add(GTK_CONTAINER(plugin), cb->ebox);
    gtk_widget_show_all(cb->ebox);

    g_signal_connect(cb->ebox, "button-press-event", G_CALLBACK(on_button_press), cb);

    xfce_panel_plugin_add_action_widget(plugin, cb->ebox);
    xfce_panel_plugin_menu_show_about(plugin);
    xfce_panel_plugin_menu_show_configure(plugin);

    g_signal_connect(plugin, "free-data", G_CALLBACK(claudebar_free), cb);

    // Kick off initial fetch and poll loop.
    refresh_snapshot(cb);
    cb->poll_id = g_timeout_add_seconds(CLAMP(cb->poll_interval, 60, 3600), on_poll_tick, cb);
}

XFCE_PANEL_PLUGIN_REGISTER(claudebar_construct);
