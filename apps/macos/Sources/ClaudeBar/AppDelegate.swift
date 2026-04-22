import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = SettingsStore.shared
        statusController = StatusItemController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusController = nil
    }
}
