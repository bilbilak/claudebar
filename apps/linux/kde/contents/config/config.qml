import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.configuration

// Plasma 6's ConfigCategory `source:` is resolved relative to the package's
// QML root — i.e. `contents/ui/` (because X-Plasma-MainScript points there) —
// NOT relative to `contents/`. Using "ui/ConfigGeneral.qml" makes Plasma look
// for `contents/ui/ui/ConfigGeneral.qml` (double `ui/`), which doesn't exist;
// it then passes null into Kirigami.PageRow's C++ push and the entire config
// dialog throws "TypeError: Passing incompatible arguments to C++ functions
// from JavaScript", leaving the General tab visibly empty.
//
// `org.kde.plasma.plasmoid` is also imported because Plasma 6's
// AppletConfiguration expects the `Plasmoid` global to be accessible to the
// config model — every working in-tree plasmoid config (systemmonitor,
// desktopcontainment) imports it.
ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "ConfigGeneral.qml"
    }
}
