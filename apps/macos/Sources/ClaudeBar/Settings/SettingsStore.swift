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
            Key.showPercentages: false,
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
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    var pollInterval: Int {
        let raw = defaults.integer(forKey: Key.pollInterval)
        return min(3600, max(60, raw))
    }
    var showPercentages: Bool { defaults.bool(forKey: Key.showPercentages) }
    var warnThreshold: Int { min(100, max(0, defaults.integer(forKey: Key.warnThreshold))) }
    var criticalThreshold: Int { min(100, max(0, defaults.integer(forKey: Key.criticalThreshold))) }
}
