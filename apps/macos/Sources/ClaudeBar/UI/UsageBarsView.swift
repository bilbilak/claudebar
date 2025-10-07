import AppKit

/// Draws two stacked rounded bars + optional percentage text inside the menu-bar button.
final class UsageBarsView: NSView {
    static let barWidth: CGFloat = 64
    static let barHeight: CGFloat = 5
    static let barGap: CGFloat = 4
    static let horizontalPadding: CGFloat = 6
    static let percentGap: CGFloat = 4
    static let percentColumnWidth: CGFloat = 34

    var snapshot: UsageSnapshot? {
        didSet { needsDisplay = true }
    }

    var showPercentages: Bool = false {
        didSet { needsDisplay = true }
    }

    static func preferredWidth(showPercentages: Bool) -> CGFloat {
        let base = horizontalPadding * 2 + barWidth
        return showPercentages ? base + percentGap + percentColumnWidth : base
    }

    override var isFlipped: Bool { false }

    /// Let the parent `NSStatusBarButton` receive clicks so the menu opens.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let settings = SettingsStore.shared
        let warn = CGFloat(settings.warnThreshold)
        let crit = CGFloat(settings.criticalThreshold)

        let totalBarHeight = Self.barHeight * 2 + Self.barGap
        let barsOriginY = (bounds.height - totalBarHeight) / 2
        let barsOriginX = Self.horizontalPadding

        let session = snapshot?.session.percent ?? 0
        let weekly = snapshot?.weekly.percent ?? 0
        let status = snapshot?.status ?? .offline

        // Top bar = session; bottom bar = weekly. Y grows up in AppKit.
        drawBar(in: ctx,
                x: barsOriginX,
                y: barsOriginY + Self.barHeight + Self.barGap,
                width: Self.barWidth, height: Self.barHeight,
                percent: session, status: status, warn: warn, crit: crit)
        drawBar(in: ctx,
                x: barsOriginX,
                y: barsOriginY,
                width: Self.barWidth, height: Self.barHeight,
                percent: weekly, status: status, warn: warn, crit: crit)

        if showPercentages {
            let pctOriginX = barsOriginX + Self.barWidth + Self.percentGap
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            let fg = NSColor.labelColor
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: fg,
                .paragraphStyle: Self.rightAlignedParagraph,
            ]
            let columnRect = NSRect(
                x: pctOriginX, y: 0,
                width: Self.percentColumnWidth, height: bounds.height
            )
            let topStr = NSAttributedString(
                string: String(format: "%.0f%%", max(0, min(100, session))),
                attributes: attrs
            )
            let botStr = NSAttributedString(
                string: String(format: "%.0f%%", max(0, min(100, weekly))),
                attributes: attrs
            )
            let topSize = topStr.size()
            let botSize = botStr.size()
            let topY = barsOriginY + Self.barHeight + Self.barGap + (Self.barHeight - topSize.height) / 2
            let botY = barsOriginY + (Self.barHeight - botSize.height) / 2
            topStr.draw(in: NSRect(x: columnRect.minX, y: topY, width: columnRect.width, height: topSize.height))
            botStr.draw(in: NSRect(x: columnRect.minX, y: botY, width: columnRect.width, height: botSize.height))
        }
    }

    private static let rightAlignedParagraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.alignment = .right
        return p
    }()

    private func drawBar(in ctx: CGContext,
                         x: CGFloat, y: CGFloat, width w: CGFloat, height h: CGFloat,
                         percent: Double, status: UsageStatus,
                         warn: CGFloat, crit: CGFloat) {
        let radius = h / 2
        let track = NSColor.labelColor.withAlphaComponent(0.22)
        let trackPath = CGPath(
            roundedRect: CGRect(x: x, y: y, width: w, height: h),
            cornerWidth: radius, cornerHeight: radius, transform: nil
        )
        ctx.addPath(trackPath)
        ctx.setFillColor(track.cgColor)
        ctx.fillPath()

        let p = CGFloat(max(0, min(100, percent)))
        guard p > 0 else { return }
        let fw = max(h, w * p / 100)
        let fill = colorFor(percent: p, status: status, warn: warn, crit: crit)
        let fillPath = CGPath(
            roundedRect: CGRect(x: x, y: y, width: fw, height: h),
            cornerWidth: radius, cornerHeight: radius, transform: nil
        )
        ctx.addPath(fillPath)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
    }

    private func colorFor(percent: CGFloat, status: UsageStatus, warn: CGFloat, crit: CGFloat) -> NSColor {
        if status != .ok {
            return NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.55, alpha: 1)
        }
        if percent >= crit {
            return NSColor(calibratedRed: 0.93, green: 0.27, blue: 0.27, alpha: 1)
        }
        if percent >= warn {
            return NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.25, alpha: 1)
        }
        return NSColor(calibratedRed: 0.26, green: 0.73, blue: 0.38, alpha: 1)
    }
}
