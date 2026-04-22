import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var snapshot: null
    property string status: "offline"

    property int warnThreshold: Plasmoid.configuration.warnThreshold
    property int criticalThreshold: Plasmoid.configuration.criticalThreshold
    property bool showPercentages: Plasmoid.configuration.showPercentages
    property int pollInterval: Math.max(60, Plasmoid.configuration.pollIntervalSeconds)
    property string helperPath: Plasmoid.configuration.helperPath || "claudebar-helper"

    Plasmoid.title: i18n("ClaudeBar")
    Plasmoid.icon: "im-claude"

    toolTipMainText: i18n("ClaudeBar")
    toolTipSubText: snapshot
        ? i18n("Session: %1% • Weekly: %2%",
               Math.round(snapshot.session.percent),
               Math.round(snapshot.weekly.percent))
        : i18n("Loading…")

    // --- DataSource: run `claudebar-helper status` and parse the JSON ------

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

    // --- Compact representation (shown in the panel) -----------------------

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

    // --- Full representation (popup on click) ------------------------------

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
