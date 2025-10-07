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

    private let sessionItem = NSMenuItem(title: String(localized: "Current session: —"), action: nil, keyEquivalent: "")
    private let sessionResetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let weeklyItem = NSMenuItem(title: String(localized: "Weekly (all models): —"), action: nil, keyEquivalent: "")
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authChanged),
            name: .claudeBarAuthChanged,
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
        button.setAccessibilityLabel(String(localized: "ClaudeBar"))
    }

    private func buildMenu() {
        menu.autoenablesItems = false

        let brand = String(localized: "ClaudeBar")
        let header = NSMenuItem(title: brand, action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: brand,
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

        let refresh = NSMenuItem(title: String(localized: "Refresh now"), action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let open = NSMenuItem(
            title: String(localized: "Open claude.ai/settings/usage"),
            action: #selector(openUsagePage), keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)

        let prefs = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: String(localized: "Quit ClaudeBar"), action: #selector(quit), keyEquivalent: "q")
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

    @objc private func authChanged() {
        Task { @MainActor in await self.refresh() }
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
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
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
        sessionItem.title = String(format: String(localized: "Current session: %d%%"), Int(s.session.percent.rounded()))
        sessionResetItem.attributedTitle = dimmed(
            String(localized: "Resets %s").replacingOccurrences(of: "%s", with: formatReset(s.session.resetsAt))
        )
        weeklyItem.title = String(format: String(localized: "Weekly (all models): %d%%"), Int(s.weekly.percent.rounded()))
        weeklyResetItem.attributedTitle = dimmed(
            String(localized: "Resets %s").replacingOccurrences(of: "%s", with: formatReset(s.weekly.resetsAt))
        )

        let statusText: String
        switch s.status {
        case .ok: statusText = ""
        case .offline: statusText = String(localized: "Offline — last value may be stale")
        case .rateLimited: statusText = String(localized: "Rate limited by Claude API")
        case .unauthenticated: statusText = String(localized: "Not signed in — open Settings to add a token")
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
        // Accessibility label is not in the catalog; compose from localized parts
        // so screen readers in non-English locales still get translated bits.
        let brand = String(localized: "ClaudeBar")
        let session = String(format: String(localized: "Current session: %d%%"), Int(s.session.percent.rounded()))
        let weekly = String(format: String(localized: "Weekly (all models): %d%%"), Int(s.weekly.percent.rounded()))
        button.setAccessibilityLabel("\(brand). \(session). \(weekly).")
    }
}

/// Human-readable reset time mirroring the GNOME indicator.
@MainActor
func formatReset(_ d: Date?) -> String {
    guard let d = d else { return String(localized: "—") }
    let delta = d.timeIntervalSinceNow
    if delta <= 0 { return String(localized: "now") }
    let mins = Int((delta / 60).rounded())
    if mins < 60 { return String(format: String(localized: "in %d min"), mins) }
    let hrs = mins / 60
    let rem = mins % 60
    if hrs < 24 {
        return rem > 0
            ? String(format: String(localized: "in %dh %dm"), hrs, rem)
            : String(format: String(localized: "in %dh"), hrs)
    }
    let days = hrs / 24
    let remH = hrs % 24
    return remH > 0
        ? String(format: String(localized: "in %dd %dh"), days, remH)
        : String(format: String(localized: "in %dd"), days)
}
