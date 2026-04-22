import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_pollIntervalSeconds: pollInterval.value
    property alias cfg_warnThreshold: warn.value
    property alias cfg_criticalThreshold: crit.value
    property alias cfg_showPercentages: showPct.checked
    property alias cfg_helperPath: helperPath.text

    SpinBox {
        id: pollInterval
        Kirigami.FormData.label: i18n("Poll interval (s):")
        from: 60
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
