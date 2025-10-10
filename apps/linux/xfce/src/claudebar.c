// SPDX-License-Identifier: GPL-3.0-or-later
// claudebar — XFCE panel plugin.
// Shells out to `claudebar-helper status` every N seconds and paints two bars.

#include <gtk/gtk.h>
#include <libxfce4panel/libxfce4panel.h>
#include <libxfce4util/libxfce4util.h>
#include <json-glib/json-glib.h>
#include <libintl.h>
#include <locale.h>
#include <math.h>
#include <string.h>

// gettext message domain. The runtime looks up translations from
// ${LOCALEDIR}/<lang>/LC_MESSAGES/${GETTEXT_PACKAGE}.mo. We use the bare
// "claudebar" domain (shared with the other Linux panel plugins) because
// scripts/regenerate-translations.py emits po/claudebar.pot — one canonical
// translation table is installed once and reused by every ClaudeBar GTK
// plugin. The build system (meson.build) overrides both macros with
// -DGETTEXT_PACKAGE / -DLOCALEDIR; the guards below let the source compile
// stand-alone for static checkers / editors.
#ifndef GETTEXT_PACKAGE
#define GETTEXT_PACKAGE "claudebar"
#endif
#ifndef LOCALEDIR
#define LOCALEDIR "/usr/share/locale"
#endif
// _() and N_() are already defined by <glib/gi18n-lib.h>, which is pulled
// in transitively via <libxfce4util/libxfce4util.h>; redefining them
// triggers `_ redefined` warnings on newer GCCs.

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
    GtkWidget       *box;            // horizontal box: bars + percent labels
    GtkWidget       *drawing;        // GtkDrawingArea showing the bars
    GtkWidget       *session_label;  // "<n>%" next to the bars
    GtkWidget       *weekly_label;
    Snapshot         snapshot;
    guint            poll_id;
    guint            poll_interval;
    guint            warn_threshold;
    guint            crit_threshold;
    gboolean         show_percentages;
    gchar           *helper_path;
    GCancellable    *cancel;
} ClaudebarPlugin;



// xfce4-panel inherits its environment from the session, which on Ubuntu /
// Mint usually means $PATH starts at /usr/local/sbin and never includes
// $HOME/.local/bin even though the user's interactive shell adds it. The
// top-level `make install-helper` installs claudebar-helper into
// ~/.local/bin by default, so a naked g_spawn_async() with SEARCH_PATH
// fails to find it. Probe the obvious locations and return an absolute
// path; callers fall back to bare "claudebar-helper" if nothing matches.
static gchar *resolve_helper_path(void) {
    const gchar *env = g_getenv("CLAUDEBAR_HELPER");
    if (env && *env && g_file_test(env, G_FILE_TEST_IS_EXECUTABLE)) {
        return g_strdup(env);
    }
    gchar *path_hit = g_find_program_in_path("claudebar-helper");
    if (path_hit) return path_hit;

    const gchar *home = g_get_home_dir();
    gchar *candidates[] = {
        home ? g_build_filename(home, ".local", "bin", "claudebar-helper", NULL) : NULL,
        g_strdup("/usr/local/bin/claudebar-helper"),
        g_strdup("/usr/bin/claudebar-helper"),
        g_strdup("/usr/libexec/claudebar-helper"),
        NULL,
    };
    gchar *found = NULL;
    for (guint i = 0; candidates[i]; i++) {
        if (!found && g_file_test(candidates[i], G_FILE_TEST_IS_EXECUTABLE)) {
            found = g_strdup(candidates[i]);
        }
        g_free(candidates[i]);
    }
    return found ? found : g_strdup("claudebar-helper");
}



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
#if GLIB_CHECK_VERSION(2, 70, 0)
    if (!g_spawn_check_wait_status(exit_status, NULL)) {
#else
    if (!g_spawn_check_exit_status(exit_status, NULL)) {
#endif
        g_free(stdout_buf);
        return NULL;
    }
    return stdout_buf;
}

static void update_labels_and_tooltip(ClaudebarPlugin *cb) {
    if (!cb->ebox) return;
    int s = (int)cb->snapshot.session_percent;
    int w = (int)cb->snapshot.weekly_percent;
    if (cb->session_label && cb->weekly_label) {
        gchar *st = g_strdup_printf("%d%%", s);
        gchar *wt = g_strdup_printf("%d%%", w);
        gtk_label_set_text(GTK_LABEL(cb->session_label), st);
        gtk_label_set_text(GTK_LABEL(cb->weekly_label),  wt);
        g_free(st); g_free(wt);
        gtk_widget_set_visible(cb->session_label, cb->show_percentages);
        gtk_widget_set_visible(cb->weekly_label,  cb->show_percentages);
    }
    gchar *tt = g_strdup_printf(_("ClaudeBar\nSession: %d%%\nWeekly: %d%%"), s, w);
    gtk_widget_set_tooltip_text(cb->ebox, tt);
    g_free(tt);
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
    update_labels_and_tooltip(cb);
}

static gboolean on_poll_tick(gpointer data) {
    refresh_snapshot((ClaudebarPlugin *)data);
    return G_SOURCE_CONTINUE;
}



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

// Empty-bar track color sampled from the GTK theme. Hardcoded white@22% was
// invisible against light panel themes; reading the widget's foreground color
// gives us a value that already contrasts with the panel background, which we
// then knock down to 18% alpha for the empty-track look.
static void theme_track_rgba(GtkWidget *widget,
                             double *r, double *g, double *b, double *a) {
    GtkStyleContext *ctx = gtk_widget_get_style_context(widget);
    GdkRGBA fg;
    gtk_style_context_get_color(ctx, gtk_style_context_get_state(ctx), &fg);
    *r = fg.red;
    *g = fg.green;
    *b = fg.blue;
    *a = 0.18;
}

static void draw_bar(GtkWidget *widget, cairo_t *cr,
                     double x, double y, double w, double h,
                     double percent, ClaudeStatus status, guint warn, guint crit) {
    double r = h / 2.0;
    double tr, tg, tb, ta;
    theme_track_rgba(widget, &tr, &tg, &tb, &ta);
    cairo_set_source_rgba(cr, tr, tg, tb, ta);
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

    draw_bar(widget, cr, 0, y_top, w, BAR_HEIGHT, cb->snapshot.session_percent,
             cb->snapshot.status, cb->warn_threshold, cb->crit_threshold);
    draw_bar(widget, cr, 0, y_bot, w, BAR_HEIGHT, cb->snapshot.weekly_percent,
             cb->snapshot.status, cb->warn_threshold, cb->crit_threshold);
    return FALSE;
}



// Re-poll status on a short cadence after sign-in launches so the bars
// update as soon as the user completes the browser OAuth flow. Without this
// the applet stays on its stale `unauthenticated` snapshot until the next
// regular poll cycle (default 5 minutes).
typedef struct {
    ClaudebarPlugin *cb;
    int polls_remaining;  // 20 × 3s = 60s
} SigninPollCtx;

static gboolean signin_poll_tick(gpointer data) {
    SigninPollCtx *ctx = (SigninPollCtx *)data;
    refresh_snapshot(ctx->cb);
    gtk_widget_queue_draw(ctx->cb->drawing);
    ctx->polls_remaining--;
    if (ctx->polls_remaining <= 0 ||
        ctx->cb->snapshot.status != STATUS_UNAUTHENTICATED) {
        g_free(ctx);
        return G_SOURCE_REMOVE;
    }
    return G_SOURCE_CONTINUE;
}

static void on_sign_in(GtkMenuItem *m G_GNUC_UNUSED, gpointer data) {
    ClaudebarPlugin *cb = (ClaudebarPlugin *)data;
    gchar *argv[3] = { cb->helper_path, "signin", NULL };
    GError *err = NULL;
    if (!g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH,
                       NULL, NULL, NULL, &err)) {
        if (err) { g_warning("claudebar: signin spawn failed: %s", err->message); g_error_free(err); }
        return;
    }
    SigninPollCtx *ctx = g_new0(SigninPollCtx, 1);
    ctx->cb = cb;
    ctx->polls_remaining = 20;
    g_timeout_add_seconds(3, signin_poll_tick, ctx);
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

static const char *status_text_for(ClaudeStatus s) {
    switch (s) {
        case STATUS_OFFLINE:        return _("Offline — last value may be stale");
        case STATUS_RATE_LIMITED:   return _("Rate limited by Claude API");
        case STATUS_UNAUTHENTICATED: return _("Not signed in — open Settings to add a token");
        default:                     return NULL;
    }
}

static gboolean on_button_press(GtkWidget *w G_GNUC_UNUSED, GdkEventButton *e, gpointer data) {
    if (e->type != GDK_BUTTON_PRESS) return FALSE;
    // Right-click belongs to the panel — it shows Properties / About / Move /
    // Remove via xfce_panel_plugin_add_action_widget(). Only handle left-click.
    if (e->button != 1) return FALSE;
    ClaudebarPlugin *cb = (ClaudebarPlugin *)data;

    GtkWidget *menu = gtk_menu_new();

    int sp = (int)cb->snapshot.session_percent;
    int wp = (int)cb->snapshot.weekly_percent;
    gchar *st = g_strdup_printf(_("Current session: %d%%"), sp);
    gchar *wt = g_strdup_printf(_("Weekly (all models): %d%%"), wp);
    GtkWidget *session_item = gtk_menu_item_new_with_label(st);
    GtkWidget *weekly_item  = gtk_menu_item_new_with_label(wt);
    gtk_widget_set_sensitive(session_item, FALSE);
    gtk_widget_set_sensitive(weekly_item,  FALSE);
    g_free(st); g_free(wt);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), session_item);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), weekly_item);

    const char *status_msg = status_text_for(cb->snapshot.status);
    if (status_msg) {
        GtkWidget *status_item = gtk_menu_item_new_with_label(status_msg);
        gtk_widget_set_sensitive(status_item, FALSE);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), status_item);
    }

    gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());

    GtkWidget *refresh = gtk_menu_item_new_with_label(_("Refresh now"));
    g_signal_connect(refresh, "activate", G_CALLBACK(on_refresh), cb);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), refresh);

    gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());

    // Show exactly one of Sign in / Sign out depending on current auth state.
    // The "offline" snapshot keeps the previously known auth state, so we treat
    // anything that isn't explicitly "unauthenticated" as signed-in (matching
    // how the tooltip / status line treat it).
    if (cb->snapshot.status == STATUS_UNAUTHENTICATED) {
        GtkWidget *signin = gtk_menu_item_new_with_label(_("Sign in with Claude"));
        g_signal_connect(signin, "activate", G_CALLBACK(on_sign_in), cb);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), signin);
    } else {
        GtkWidget *signout = gtk_menu_item_new_with_label(_("Sign out"));
        g_signal_connect(signout, "activate", G_CALLBACK(on_sign_out), cb);
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), signout);
    }

    gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());

    GtkWidget *open_u = gtk_menu_item_new_with_label(_("Open claude.ai/settings/usage"));
    g_signal_connect(open_u, "activate", G_CALLBACK(on_open_usage), cb);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), open_u);

    gtk_widget_show_all(menu);
    gtk_menu_popup_at_pointer(GTK_MENU(menu), (GdkEvent *)e);
    return TRUE;
}



#ifndef CLAUDEBAR_VERSION
#define CLAUDEBAR_VERSION "0.0.0"
#endif

// Forward decl — save_config() is defined further down with the other
// XfceRc-based config helpers but called from the configure dialog's
// "Close" path immediately below.
static void save_config(ClaudebarPlugin *cb);

static void on_about(XfcePanelPlugin *plugin G_GNUC_UNUSED, gpointer data G_GNUC_UNUSED) {
    const char *authors[] = { "Bilbilak", NULL };
    GtkWidget *dlg = gtk_about_dialog_new();
    gtk_about_dialog_set_program_name (GTK_ABOUT_DIALOG(dlg), "ClaudeBar");
    gtk_about_dialog_set_version      (GTK_ABOUT_DIALOG(dlg), CLAUDEBAR_VERSION);
    gtk_about_dialog_set_logo_icon_name(GTK_ABOUT_DIALOG(dlg), "claudebar");
    gtk_about_dialog_set_comments     (GTK_ABOUT_DIALOG(dlg),
        _("Shows Claude.ai Max-plan session and weekly usage as two bars."));
    gtk_about_dialog_set_website      (GTK_ABOUT_DIALOG(dlg), "https://github.com/bilbilak/claudebar");
    gtk_about_dialog_set_website_label(GTK_ABOUT_DIALOG(dlg), "github.com/bilbilak/claudebar");
    gtk_about_dialog_set_license_type (GTK_ABOUT_DIALOG(dlg), GTK_LICENSE_GPL_3_0);
    gtk_about_dialog_set_authors      (GTK_ABOUT_DIALOG(dlg), authors);
    gtk_about_dialog_set_copyright    (GTK_ABOUT_DIALOG(dlg), "© 2025–2026 Bilbilak");
    gtk_dialog_run(GTK_DIALOG(dlg));
    gtk_widget_destroy(dlg);
}



static void on_signin_clicked (GtkButton *b G_GNUC_UNUSED, gpointer data) { on_sign_in (NULL, data); }
static void on_signout_clicked(GtkButton *b G_GNUC_UNUSED, gpointer data) { on_sign_out(NULL, data); }

static void on_configure(XfcePanelPlugin *plugin, gpointer data) {
    ClaudebarPlugin *cb = (ClaudebarPlugin *)data;
    xfce_panel_plugin_block_menu(plugin);

    GtkWidget *dlg = gtk_dialog_new_with_buttons(
        _("ClaudeBar — Preferences"), NULL,
        GTK_DIALOG_DESTROY_WITH_PARENT,
        _("_Close"), GTK_RESPONSE_CLOSE, NULL);
    gtk_window_set_icon_name(GTK_WINDOW(dlg), "claudebar");
    gtk_container_set_border_width(GTK_CONTAINER(dlg), 10);

    GtkWidget *content = gtk_dialog_get_content_area(GTK_DIALOG(dlg));
    GtkWidget *grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(grid), 8);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 12);
    gtk_container_add(GTK_CONTAINER(content), grid);

    int row = 0;

    // Account
    GtkWidget *signin_btn  = gtk_button_new_with_label(_("Sign in with Claude"));
    GtkWidget *signout_btn = gtk_button_new_with_label(_("Sign out"));
    GtkWidget *acc_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_box_pack_start(GTK_BOX(acc_box), signin_btn,  FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(acc_box), signout_btn, FALSE, FALSE, 0);
    g_signal_connect(signin_btn,  "clicked", G_CALLBACK(on_signin_clicked),  cb);
    g_signal_connect(signout_btn, "clicked", G_CALLBACK(on_signout_clicked), cb);
    // Pre-show both so gtk_widget_show_all() doesn't clobber our state, then
    // hide the irrelevant one based on the current snapshot. The dialog isn't
    // long-lived enough to bother wiring a live update.
    gboolean unauth = (cb->snapshot.status == STATUS_UNAUTHENTICATED);
    gtk_widget_set_no_show_all(unauth ? signout_btn : signin_btn, TRUE);
    gtk_widget_set_visible    (unauth ? signout_btn : signin_btn, FALSE);
    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(_("Account")), 0, row, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), acc_box,                       1, row, 1, 1);
    row++;

    // Poll interval
    GtkWidget *poll = gtk_spin_button_new_with_range(120, 3600, 30);
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(poll), cb->poll_interval);
    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(_("Poll interval (seconds)")), 0, row, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), poll,                                          1, row, 1, 1);
    row++;

    // Show percentages
    GtkWidget *show_pct = gtk_check_button_new_with_label(_("Show numeric percentages next to bars"));
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(show_pct), cb->show_percentages);
    gtk_grid_attach(GTK_GRID(grid), show_pct, 0, row, 2, 1);
    row++;

    // Warn / Crit
    GtkWidget *warn = gtk_spin_button_new_with_range(0, 100, 5);
    GtkWidget *crit = gtk_spin_button_new_with_range(0, 100, 5);
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(warn), cb->warn_threshold);
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(crit), cb->crit_threshold);
    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(_("Orange at (%)")), 0, row, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), warn,                              1, row, 1, 1); row++;
    gtk_grid_attach(GTK_GRID(grid), gtk_label_new(_("Red at (%)")),    0, row, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), crit,                              1, row, 1, 1); row++;

    gtk_widget_show_all(dlg);
    gtk_dialog_run(GTK_DIALOG(dlg));

    cb->poll_interval    = gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(poll));
    cb->warn_threshold   = gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(warn));
    cb->crit_threshold   = gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(crit));
    cb->show_percentages = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(show_pct));

    gtk_widget_destroy(dlg);
    xfce_panel_plugin_unblock_menu(plugin);

    // Re-arm poll timer + refresh visuals.
    if (cb->poll_id) { g_source_remove(cb->poll_id); cb->poll_id = 0; }
    cb->poll_id = g_timeout_add_seconds(CLAMP(cb->poll_interval, 120, 3600), on_poll_tick, cb);
    update_labels_and_tooltip(cb);
    if (cb->drawing) gtk_widget_queue_draw(cb->drawing);
    save_config(cb);
}



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
    xfce_rc_write_bool_entry(rc, "show_percentages", cb->show_percentages);
    xfce_rc_write_entry(rc, "helper_path", cb->helper_path ? cb->helper_path : "claudebar-helper");
    xfce_rc_close(rc);
}

static void load_config(ClaudebarPlugin *cb) {
    cb->poll_interval = DEFAULT_POLL_INTERVAL;
    cb->warn_threshold = DEFAULT_WARN;
    cb->crit_threshold = DEFAULT_CRIT;
    cb->show_percentages = TRUE;
    cb->helper_path = resolve_helper_path();

    gchar *file = xfce_panel_plugin_save_location(cb->plugin, FALSE);
    if (!file) return;
    XfceRc *rc = xfce_rc_simple_open(file, TRUE);
    g_free(file);
    if (!rc) return;
    xfce_rc_set_group(rc, "general");
    cb->poll_interval  = (guint)xfce_rc_read_int_entry(rc, "poll_interval", DEFAULT_POLL_INTERVAL);
    cb->warn_threshold = (guint)xfce_rc_read_int_entry(rc, "warn",          DEFAULT_WARN);
    cb->crit_threshold = (guint)xfce_rc_read_int_entry(rc, "crit",          DEFAULT_CRIT);
    cb->show_percentages = xfce_rc_read_bool_entry(rc, "show_percentages", TRUE);
    // Only override the resolved default if the user has an explicit value
    // saved; otherwise resolve_helper_path()'s probe wins. Reading with a
    // NULL fallback returns NULL for missing/empty keys.
    const gchar *hp = xfce_rc_read_entry(rc, "helper_path", NULL);
    if (hp && *hp) {
        g_free(cb->helper_path);
        cb->helper_path = g_strdup(hp);
    }
    xfce_rc_close(rc);
}



static void claudebar_free(XfcePanelPlugin *plugin, ClaudebarPlugin *cb) {
    (void)plugin;
    if (cb->poll_id) { g_source_remove(cb->poll_id); cb->poll_id = 0; }
    save_config(cb);
    g_free(cb->helper_path);
    g_free(cb);
}

// Bind the gettext domain. Safe to call multiple times — gettext deduplicates.
static void claudebar_init_i18n(void) {
    static gboolean done = FALSE;
    if (done) return;
    done = TRUE;
    // setlocale() is normally called by GTK already; we set LC_MESSAGES
    // defensively in case the plugin is loaded into a host that did not.
    setlocale(LC_ALL, "");
    bindtextdomain(GETTEXT_PACKAGE, LOCALEDIR);
    bind_textdomain_codeset(GETTEXT_PACKAGE, "UTF-8");
    textdomain(GETTEXT_PACKAGE);
}

static void claudebar_construct(XfcePanelPlugin *plugin) {
    claudebar_init_i18n();

    ClaudebarPlugin *cb = g_new0(ClaudebarPlugin, 1);
    cb->plugin = plugin;
    load_config(cb);
    snapshot_reset(&cb->snapshot, STATUS_OFFLINE);

    cb->ebox = gtk_event_box_new();
    gtk_event_box_set_visible_window(GTK_EVENT_BOX(cb->ebox), FALSE);
    // Without above_child, events on our windowless children (drawing area,
    // labels) sink into the panel's GdkWindow and never propagate back here,
    // so clicks reach neither our menu nor xfce_panel_plugin_add_action_widget.
    gtk_event_box_set_above_child(GTK_EVENT_BOX(cb->ebox), TRUE);
    gtk_widget_add_events(cb->ebox, GDK_BUTTON_PRESS_MASK);

    cb->box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_container_add(GTK_CONTAINER(cb->ebox), cb->box);

    cb->drawing = gtk_drawing_area_new();
    gtk_widget_set_size_request(cb->drawing, BAR_WIDTH, BAR_HEIGHT * 2 + BAR_GAP + 8);
    gtk_widget_set_valign(cb->drawing, GTK_ALIGN_CENTER);
    g_signal_connect(cb->drawing, "draw", G_CALLBACK(on_draw), cb);
    gtk_box_pack_start(GTK_BOX(cb->box), cb->drawing, FALSE, FALSE, 0);

    GtkWidget *pct_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
    gtk_widget_set_valign(pct_box, GTK_ALIGN_CENTER);
    cb->session_label = gtk_label_new("");
    cb->weekly_label  = gtk_label_new("");
    gtk_widget_set_halign(cb->session_label, GTK_ALIGN_END);
    gtk_widget_set_halign(cb->weekly_label,  GTK_ALIGN_END);
    PangoAttrList *attrs = pango_attr_list_new();
    pango_attr_list_insert(attrs, pango_attr_size_new(8 * PANGO_SCALE));
    gtk_label_set_attributes(GTK_LABEL(cb->session_label), attrs);
    gtk_label_set_attributes(GTK_LABEL(cb->weekly_label),  attrs);
    pango_attr_list_unref(attrs);
    gtk_box_pack_start(GTK_BOX(pct_box), cb->session_label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(pct_box), cb->weekly_label,  FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(cb->box), pct_box, FALSE, FALSE, 0);

    gtk_container_add(GTK_CONTAINER(plugin), cb->ebox);
    gtk_widget_show_all(cb->ebox);

    g_signal_connect(cb->ebox, "button-press-event", G_CALLBACK(on_button_press), cb);

    xfce_panel_plugin_add_action_widget(plugin, cb->ebox);
    xfce_panel_plugin_menu_show_about(plugin);
    xfce_panel_plugin_menu_show_configure(plugin);

    g_signal_connect(plugin, "free-data",       G_CALLBACK(claudebar_free), cb);
    g_signal_connect(plugin, "about",           G_CALLBACK(on_about),       cb);
    g_signal_connect(plugin, "configure-plugin",G_CALLBACK(on_configure),   cb);

    // Kick off initial fetch and poll loop.
    refresh_snapshot(cb);
    cb->poll_id = g_timeout_add_seconds(CLAMP(cb->poll_interval, 120, 3600), on_poll_tick, cb);
}

XFCE_PANEL_PLUGIN_REGISTER(claudebar_construct);
