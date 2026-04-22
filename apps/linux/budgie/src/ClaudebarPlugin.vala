// SPDX-License-Identifier: GPL-3.0-or-later

public class ClaudebarPlugin : GLib.Object, Budgie.Plugin {
    public Budgie.Applet get_panel_widget(string uuid) {
        return new ClaudebarApplet(uuid);
    }
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
    var objmod = module as Peas.ObjectModule;
    objmod.register_extension_type(typeof(Budgie.Plugin), typeof(ClaudebarPlugin));
}
