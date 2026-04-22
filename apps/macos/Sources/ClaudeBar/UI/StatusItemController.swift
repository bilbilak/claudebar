import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let barsView: UsageBarsView
    private let menu = NSMenu()
    private let source = UsageSource()

    private var snapshot: UsageSnapshot?
    private var pollTimer: Timer?
    private var refreshInFlight = false
    private var prefsController: PreferencesWindowController?

    private let sessionItem = NSMenuItem(title: "Current session: —", action: nil, keyEquivalent: "")
    private let sessionResetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let weeklyItem = NSMenuItem(title: "Weekly (all models): —", action: nil, keyEquivalent: "")
    private let weeklyResetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let statusItemLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    override init() {
        let length = UsageBarsView.preferredWidth(showPercentages: SettingsStore.shared.showPercentages)
        self.statusItem = NSStatusBar.system.statusItem(withLength: length)
        self.barsView = UsageBarsView(frame: .zero)
        super.init()

        configureStatusItem(length: length)
        buildMenu()
        statusItem.menu = menu

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: SettingsStore.didChangeNotification,
            object: nil
        )

        startPolling()
        Task { await self.refresh() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pollTimer?.invalidate()
    }

    // MARK: - Setup

    private func configureStatusItem(length: CGFloat) {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = ""
        button.imagePosition = .noImage
        button.wantsLayer = true
        button.translatesAutoresizingMaskIntoConstraints = true

        barsView.frame = NSRect(x: 0, y: 0, width: length, height: NSStatusBar.system.thickness)
        barsView.autoresizingMask = [.width, .height]
        barsView.showPercentages = SettingsStore.shared.showPercentages
        button.addSubview(barsView)
        button.setAccessibilityRole(.menuButton)
        button.setAccessibilityLabel("ClaudeBar")
    }

    private func buildMenu() {
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "ClaudeBar", action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: "ClaudeBar",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        sessionItem.isEnabled = false
        menu.addItem(sessionItem)
        sessionResetItem.isEnabled = false
        sessionResetItem.attributedTitle = dimmed("")
        menu.addItem(sessionResetItem)

        weeklyItem.isEnabled = false
        menu.addItem(weeklyItem)
        weeklyResetItem.isEnabled = false
        weeklyResetItem.attributedTitle = dimmed("")
        menu.addItem(weeklyResetItem)

        statusItemLine.isEnabled = false
        statusItemLine.isHidden = true
        menu.addItem(statusItemLine)

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let open = NSMenuItem(
            title: "Open claude.ai/settings/usage",
            action: #selector(openUsagePage), keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)

        let prefs = NSMenuItem(title: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit ClaudeBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func dimmed(_ s: String) -> NSAttributedString {
        NSAttributedString(
            string: s,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        Task { await self.refresh() }
    }

    @objc private func openUsagePage() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openPreferences() {
        if prefsController == nil {
            prefsController = PreferencesWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsController?.showWindow(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func settingsChanged() {
        let length = UsageBarsView.preferredWidth(showPercentages: SettingsStore.shared.showPercentages)
        statusItem.length = length
        barsView.showPercentages = SettingsStore.shared.showPercentages
        barsView.frame = NSRect(x: 0, y: 0, width: length, height: NSStatusBar.system.thickness)
        barsView.needsDisplay = true
        restartPolling()
    }

    // MARK: - Polling / refresh

    private func startPolling() {
        pollTimer?.invalidate()
        let interval = TimeInterval(SettingsStore.shared.pollInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func restartPolling() {
        startPolling()
    }

    private func refresh() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }

        let snap = await source.fetch()
        self.snapshot = snap
        self.barsView.snapshot = snap
        updateMenuLabels()
        updateAccessibility()
    }

    private func updateMenuLabels() {
        guard let s = snapshot else { return }
        sessionItem.title = String(format: "Current session: %.0f%%", s.session.percent)
        sessionResetItem.attributedTitle = dimmed("Resets \(formatReset(s.session.resetsAt))")
        weeklyItem.title = String(format: "Weekly (all models): %.0f%%", s.weekly.percent)
        weeklyResetItem.attributedTitle = dimmed("Resets \(formatReset(s.weekly.resetsAt))")

        let statusText: String
        switch s.status {
        case .ok: statusText = ""
        case .offline: statusText = "Offline — last value may be stale"
        case .rateLimited: statusText = "Rate limited by Claude API"
        case .unauthenticated: statusText = "Not signed in — open Settings to add a token"
        }
        statusItemLine.attributedTitle = NSAttributedString(
            string: statusText,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .obliqueness: NSNumber(value: 0.1),
            ]
        )
        statusItemLine.isHidden = statusText.isEmpty
    }

    private func updateAccessibility() {
        guard let s = snapshot, let button = statusItem.button else { return }
        button.setAccessibilityLabel(
            String(
                format: "ClaudeBar. Session %.0f percent. Weekly %.0f percent.",
                s.session.percent, s.weekly.percent
            )
        )
    }
}

/// Human-readable reset time mirroring the GNOME indicator.
@MainActor
func formatReset(_ d: Date?) -> String {
    guard let d = d else { return "—" }
    let delta = d.timeIntervalSinceNow
    if delta <= 0 { return "now" }
    let mins = Int((delta / 60).rounded())
    if mins < 60 { return "in \(mins) min" }
    let hrs = mins / 60
    let rem = mins % 60
    if hrs < 24 {
        return rem > 0 ? "in \(hrs)h \(rem)m" : "in \(hrs)h"
    }
    let days = hrs / 24
    let remH = hrs % 24
    return remH > 0 ? "in \(days)d \(remH)h" : "in \(days)d"
}
