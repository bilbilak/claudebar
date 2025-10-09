import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// Plasma 6's AppletConfiguration shell pushes each ConfigCategory into a
// Kirigami.PageRow, which requires a Page-derived component at the top
// level — a bare Kirigami.FormLayout root crashes the loader with
// "TypeError: Passing incompatible arguments to C++ functions from JavaScript",
// leaving the General tab visibly empty.
//
// KCM.SimpleKCM is the standard wrapper for KCM-like config pages in
// Plasma 6 / KF6; the cfg_* aliases live at the SimpleKCM root so the
// plasmoid config system can bind them to the entries in main.xml.
KCM.SimpleKCM {
    property alias cfg_pollIntervalSeconds: pollInterval.value
    property alias cfg_warnThreshold: warn.value
    property alias cfg_criticalThreshold: crit.value
    property alias cfg_showPercentages: showPct.checked
    property alias cfg_helperPath: helperPath.text

    Kirigami.FormLayout {
        SpinBox {
            id: pollInterval
            Kirigami.FormData.label: i18n("Poll interval (s):")
            from: 120
            to: 3600
            stepSize: 30
        }

        SpinBox {
            id: warn
            Kirigami.FormData.label: i18n("Orange at (%):")
            from: 0
            to: 100
            stepSize: 5
        }

        SpinBox {
            id: crit
            Kirigami.FormData.label: i18n("Red at (%):")
            from: 0
            to: 100
            stepSize: 5
        }

        CheckBox {
            id: showPct
            Kirigami.FormData.label: i18n("Labels:")
            text: i18n("Show numeric percentages beside the bars")
        }

        TextField {
            id: helperPath
            Kirigami.FormData.label: i18n("Helper binary:")
            placeholderText: i18n("claudebar-helper")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        }
    }
}
