import Foundation

/// Persisted user preferences. Mirrors the GSettings schema from the GNOME extension.
/// Backed by `UserDefaults.standard` so SwiftUI's `@AppStorage` binds to the same store.
final class SettingsStore {
    static let shared = SettingsStore()

    enum Key {
        static let pollInterval = "pollIntervalSeconds"
        static let showPercentages = "showPercentages"
        static let warnThreshold = "warnThreshold"
        static let criticalThreshold = "criticalThreshold"
    }

    static let didChangeNotification = Notification.Name("ClaudeBarSettingsDidChange")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.pollInterval: 300,
            Key.showPercentages: true,
            Key.warnThreshold: 60,
            Key.criticalThreshold: 85,
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func userDefaultsChanged() {
        // UserDefaults.didChangeNotification can fire on a background thread.
        // Our subscribers (e.g. StatusItemController.settingsChanged) touch
        // AppKit views (barsView.needsDisplay, statusItem.length) which only
        // honor mutations on the main thread — off-main updates silently
        // no-op. Always re-broadcast on main so the menu-bar UI actually
        // refreshes when the user toggles a setting.
        if Thread.isMainThread {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            }
        }
    }

    var pollInterval: Int {
        let raw = defaults.integer(forKey: Key.pollInterval)
        return min(3600, max(120, raw))
    }
    var showPercentages: Bool { defaults.bool(forKey: Key.showPercentages) }
    var warnThreshold: Int { min(100, max(0, defaults.integer(forKey: Key.warnThreshold))) }
    var criticalThreshold: Int { min(100, max(0, defaults.integer(forKey: Key.criticalThreshold))) }
}
