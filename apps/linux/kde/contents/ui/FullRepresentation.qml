import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property var snapshot: null
    property string status: "offline"

    signal refreshRequested()
    signal openUsagePage()
    signal signInRequested()

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 10
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Heading {
        level: 2
        text: i18n("ClaudeBar")
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Kirigami.Theme.disabledTextColor
        opacity: 0.25
    }

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Label {
            text: root.snapshot
                ? i18n("Current session: %1%",
                       Math.round(root.snapshot.session.percent))
                : i18n("Current session: —")
            font.bold: true
        }
        Label {
            text: i18n("Resets %1", formatReset(root.snapshot && root.snapshot.session.resets_at))
            opacity: 0.7
        }

        Label {
            text: root.snapshot
                ? i18n("Weekly (all models): %1%",
                       Math.round(root.snapshot.weekly.percent))
                : i18n("Weekly (all models): —")
            font.bold: true
            Layout.topMargin: Kirigami.Units.smallSpacing
        }
        Label {
            text: i18n("Resets %1", formatReset(root.snapshot && root.snapshot.weekly.resets_at))
            opacity: 0.7
        }

        Label {
            visible: text.length > 0
            font.italic: true
            opacity: 0.6
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: {
                switch (root.status) {
                case "offline": return i18n("Offline — last value may be stale");
                case "rate-limited": return i18n("Rate limited by Claude API");
                case "unauthenticated": return i18n("Not signed in — click 'Sign in' below");
                default: return "";
                }
            }
        }
    }

    Item { Layout.fillHeight: true }

    RowLayout {
        Layout.fillWidth: true
        Button {
            text: i18n("Refresh now")
            onClicked: root.refreshRequested()
        }
        Button {
            text: i18n("Open claude.ai/settings/usage")
            onClicked: root.openUsagePage()
        }
        Item { Layout.fillWidth: true }
        Button {
            text: root.status === "unauthenticated" ? i18n("Sign in") : i18n("Re-authenticate")
            onClicked: root.signInRequested()
        }
    }

    function formatReset(iso) {
        if (!iso) return "—";
        const then = new Date(iso);
        const now = new Date();
        const deltaMs = then - now;
        if (deltaMs <= 0) return i18n("now");
        const mins = Math.round(deltaMs / 60000);
        if (mins < 60) return i18n("in %1 min", mins);
        const hrs = Math.floor(mins / 60);
        const rem = mins % 60;
        if (hrs < 24) {
            return rem > 0 ? i18n("in %1h %2m", hrs, rem) : i18n("in %1h", hrs);
        }
        const days = Math.floor(hrs / 24);
        const remH = hrs % 24;
        return remH > 0 ? i18n("in %1d %2h", days, remH) : i18n("in %1d", days);
    }
}
