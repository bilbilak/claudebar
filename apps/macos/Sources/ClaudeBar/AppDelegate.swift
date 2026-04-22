import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = SettingsStore.shared
        statusController = StatusItemController()
        registerAsLoginItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusController = nil
    }

    private func registerAsLoginItem() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            // Silently ignore — user can toggle via System Settings → General → Login Items.
        }
    }
}
