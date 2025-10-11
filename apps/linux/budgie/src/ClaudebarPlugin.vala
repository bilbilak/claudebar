// SPDX-License-Identifier: GPL-3.0-or-later

public class ClaudebarPlugin : GLib.Object, Budgie.Plugin {
    public Budgie.Applet get_panel_widget(string uuid) {
        return new ClaudebarApplet(uuid);
    }
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
    // Bind the gettext text domain so _() resolves to translated strings
    // installed alongside the plugin (typically /usr/share/locale).
    Intl.bindtextdomain(Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
    Intl.bind_textdomain_codeset(Config.GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain(Config.GETTEXT_PACKAGE);

    var objmod = module as Peas.ObjectModule;
    objmod.register_extension_type(typeof(Budgie.Plugin), typeof(ClaudebarPlugin));
}
