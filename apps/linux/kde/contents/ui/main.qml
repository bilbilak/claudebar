import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

// i18n / KI18n wiring
// Plasma 6 plasmoids resolve their translation catalog via the
// `X-KPackage-DomainName` field in `metadata.json` (set to "claudebar"). When
// KPackage loads the plasmoid, plasmaquick's KLocalizedContext picks up that
// domain and binds it to all `i18n()` / `i18nc()` calls in this QML tree, so
// there is no explicit JS-side registration needed here. The compiled `.mo`
// files are looked up under
// `~/.local/share/plasma/plasmoids/<id>/contents/locale/<lang>/LC_MESSAGES/claudebar.mo`
// (installed by `make install`). As a fallback, the `install-translations`
// target also drops them into `~/.local/share/locale/<lang>/LC_MESSAGES/` so
// systems where Plasma's per-package lookup misses still get translations.
PlasmoidItem {
    id: root

    property var snapshot: null
    property string status: "offline"

    property int warnThreshold: Plasmoid.configuration.warnThreshold
    property int criticalThreshold: Plasmoid.configuration.criticalThreshold
    property bool showPercentages: Plasmoid.configuration.showPercentages
    property int pollInterval: Math.max(120, Plasmoid.configuration.pollIntervalSeconds)
    property string helperPath: Plasmoid.configuration.helperPath || "claudebar-helper"

    Plasmoid.title: i18n("ClaudeBar")
    Plasmoid.icon: "claudebar"

    toolTipMainText: i18n("ClaudeBar")
    toolTipSubText: snapshot
        ? i18n("Session: %1% • Weekly: %2%",
               Math.round(snapshot.session.percent),
               Math.round(snapshot.weekly.percent))
        : i18n("Loading…")

    Plasma5Support.DataSource {
        id: helperDs
        engine: "executable"
        connectedSources: []

        function pollNow() {
            const cmd = helperPath + " status";
            // Re-connect to retrigger; disconnect first to avoid duplicates.
            disconnectSource(cmd);
            connectSource(cmd);
        }

        onNewData: (sourceName, data) => {
            if (data["exit code"] !== 0) {
                root.status = "offline";
                return;
            }
            try {
                const parsed = JSON.parse(data.stdout);
                root.snapshot = parsed;
                root.status = parsed.status;
            } catch (e) {
                root.status = "offline";
            }
            disconnectSource(sourceName);
        }
    }

    Timer {
        interval: root.pollInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: helperDs.pollNow()
    }

    compactRepresentation: UsageBars {
        snapshot: root.snapshot
        status: root.status
        warnThreshold: root.warnThreshold
        criticalThreshold: root.criticalThreshold
        showPercentages: root.showPercentages

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: FullRepresentation {
        snapshot: root.snapshot
        status: root.status
        onRefreshRequested: helperDs.pollNow()
        onOpenUsagePage: Qt.openUrlExternally("https://claude.ai/settings/usage")
        onSignInRequested: {
            // Launch a detached `claudebar-helper signin` process.
            signInDs.connectSource(helperPath + " signin");
        }
    }

    Plasma5Support.DataSource {
        id: signInDs
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, _data) => {
            disconnectSource(sourceName);
            helperDs.pollNow();
        }
    }
}
