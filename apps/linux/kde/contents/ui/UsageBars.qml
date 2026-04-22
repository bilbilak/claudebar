import QtQuick

// Draws the two stacked usage bars that live in the panel.
Item {
    id: root

    property var snapshot: null
    property string status: "offline"
    property int warnThreshold: 60
    property int criticalThreshold: 85
    property bool showPercentages: false

    readonly property real sessionPercent: snapshot ? snapshot.session.percent : 0
    readonly property real weeklyPercent: snapshot ? snapshot.weekly.percent : 0

    // Size ourselves relative to the panel thickness.
    implicitWidth: showPercentages ? 88 : 64
    implicitHeight: 24
    Layout.fillHeight: true

    Canvas {
        id: bars
        anchors.fill: parent
        anchors.margins: 2

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const barHeight = Math.max(4, Math.floor(height * 0.28));
            const gap = Math.max(2, Math.floor(height * 0.14));
            const labelSpace = root.showPercentages ? 28 : 0;
            const barsWidth = Math.max(24, width - labelSpace - 4);
            const x = 0;
            const totalH = barHeight * 2 + gap;
            const yTop = (height - totalH) / 2;
            const yBot = yTop + barHeight + gap;

            drawBar(ctx, x, yTop, barsWidth, barHeight, root.sessionPercent, root.status);
            drawBar(ctx, x, yBot, barsWidth, barHeight, root.weeklyPercent, root.status);

            if (root.showPercentages) {
                ctx.fillStyle = "rgba(255,255,255,0.92)";
                ctx.font = "600 9px Segoe UI, Noto Sans, sans-serif";
                ctx.textAlign = "right";
                ctx.textBaseline = "middle";
                ctx.fillText(Math.round(root.sessionPercent) + "%", width, yTop + barHeight / 2);
                ctx.fillText(Math.round(root.weeklyPercent) + "%", width, yBot + barHeight / 2);
            }
        }

        function drawBar(ctx, x, y, w, h, percent, status) {
            const r = h / 2;
            roundedRect(ctx, x, y, w, h, r);
            ctx.fillStyle = "rgba(255,255,255,0.22)";
            ctx.fill();
            const p = Math.max(0, Math.min(100, percent));
            if (p <= 0) return;
            const fw = Math.max(h, w * p / 100);
            roundedRect(ctx, x, y, fw, h, r);
            ctx.fillStyle = colorFor(p, status);
            ctx.fill();
        }

        function roundedRect(ctx, x, y, w, h, r) {
            ctx.beginPath();
            ctx.moveTo(x + r, y);
            ctx.lineTo(x + w - r, y);
            ctx.quadraticCurveTo(x + w, y, x + w, y + r);
            ctx.lineTo(x + w, y + h - r);
            ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
            ctx.lineTo(x + r, y + h);
            ctx.quadraticCurveTo(x, y + h, x, y + h - r);
            ctx.lineTo(x, y + r);
            ctx.quadraticCurveTo(x, y, x + r, y);
            ctx.closePath();
        }

        function colorFor(percent, status) {
            if (status !== "ok") return "rgb(160,160,160)";
            if (percent >= root.criticalThreshold) return "rgb(237,68,68)";
            if (percent >= root.warnThreshold) return "rgb(245,158,63)";
            return "rgb(66,186,96)";
        }
    }

    // Trigger repaint whenever inputs change.
    onSnapshotChanged: bars.requestPaint()
    onStatusChanged: bars.requestPaint()
    onWarnThresholdChanged: bars.requestPaint()
    onCriticalThresholdChanged: bars.requestPaint()
    onShowPercentagesChanged: bars.requestPaint()
}
