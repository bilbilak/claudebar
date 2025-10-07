import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    convenience init() {
        let hosting = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = String(localized: "ClaudeBar")
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 540, height: 440))
        window.center()
        self.init(window: window)
        window.delegate = self
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct PreferencesView: View {
    var body: some View {
        TabView {
            AccountPane()
                .tabItem { Label(String(localized: "Account"), systemImage: "person.crop.circle") }
            DisplayPane()
                .tabItem { Label(String(localized: "Display"), systemImage: "paintbrush") }
            AdvancedPane()
                .tabItem { Label(String(localized: "Advanced"), systemImage: "gearshape") }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 400)
    }
}

// MARK: - Account

struct AccountPane: View {
    @State private var status: String = String(localized: "Checking…")
    @State private var signedIn: Bool = false
    @State private var inProgress: Bool = false
    @State private var errorMessage: String?
    @State private var currentLogin: OAuth.LoginFlow?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Authentication"))
                .font(.headline)
            // NOTE: catalog text mentions "GNOME Keyring via libsecret" because the
            // master string is shared across platforms; on macOS this is read from
            // the Keychain. Until the catalog gains a macOS variant we keep the
            // user-visible copy accurate via this dedicated string (not in YAML).
            Text("Sign in with your Claude account to fetch Max-plan usage. Tokens are encrypted at rest in the macOS Keychain.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Status"))
                Text(status).foregroundColor(.secondary)
                Spacer()
                if signedIn {
                    Button(String(localized: "Sign out")) { signOut() }
                        .disabled(inProgress)
                } else {
                    Button(String(localized: "Sign in with Claude")) { signIn() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(inProgress)
                }
            }

            if inProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Waiting for browser sign-in…"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let url = currentLogin?.authorizeURL {
                        Button(String(localized: "Copy link")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        }
                    }
                    Button(String(localized: "Cancel")) { cancel() }
                }
            }

            if let msg = errorMessage, !msg.isEmpty {
                Text(msg)
                    .font(.callout)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
        .task { await refreshStatus() }
    }

    private func refreshStatus() async {
        if let t = await Keychain.shared.loadTokens() {
            let tail = String(t.accessToken.suffix(6))
            status = String(localized: "Signed in (token ends '…%s')")
                .replacingOccurrences(of: "%s", with: tail)
            signedIn = true
        } else {
            status = String(localized: "Not signed in")
            signedIn = false
        }
    }

    private func signIn() {
        errorMessage = nil
        do {
            let flow = try OAuth.startLoginFlow()
            currentLogin = flow
            inProgress = true
            NSWorkspace.shared.open(flow.authorizeURL)
            Task {
                do {
                    let tokens = try await flow.result()
                    await Keychain.shared.storeTokens(tokens)
                    NotificationCenter.default.post(name: .claudeBarAuthChanged, object: nil)
                    await refreshStatus()
                } catch {
                    errorMessage = (error as NSError).localizedDescription
                }
                inProgress = false
                currentLogin = nil
            }
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    private func cancel() {
        currentLogin?.cancel()
        currentLogin = nil
        inProgress = false
    }

    private func signOut() {
        Task {
            await Keychain.shared.clearTokens()
            NotificationCenter.default.post(name: .claudeBarAuthChanged, object: nil)
            await refreshStatus()
        }
    }
}

// MARK: - Display

struct DisplayPane: View {
    @AppStorage(SettingsStore.Key.showPercentages) private var showPercentages: Bool = false
    @AppStorage(SettingsStore.Key.warnThreshold) private var warn: Int = 60
    @AppStorage(SettingsStore.Key.criticalThreshold) private var crit: Int = 85

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // "Menu bar" is the macOS equivalent of the cross-platform "Top bar"
            // string — they describe the same UI element on different platforms.
            Text(String(localized: "Top bar"))
                .font(.headline)
            Toggle(String(localized: "Show numeric percentages next to bars"), isOn: $showPercentages)
                .toggleStyle(.switch)
            Text(String(localized: "Small session and weekly percentages, stacked beside the bars."))
                .font(.callout)
                .foregroundColor(.secondary)

            Divider()

            Text(String(localized: "Color thresholds"))
                .font(.headline)
            Text(String(localized: "When bars switch from green to orange to red."))
                .font(.callout)
                .foregroundColor(.secondary)

            stepperRow(title: String(localized: "Orange at (%)"), value: $warn)
            stepperRow(title: String(localized: "Red at (%)"), value: $crit)

            Spacer()
        }
        .padding()
    }

    private func stepperRow(title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: value, in: 0...100, step: 5) {
                Text("\(value.wrappedValue)%")
                    .frame(minWidth: 48, alignment: .trailing)
                    .monospacedDigit()
            }
            .labelsHidden()
            Text("\(value.wrappedValue)%")
                .frame(minWidth: 44, alignment: .trailing)
                .monospacedDigit()
        }
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @AppStorage(SettingsStore.Key.pollInterval) private var interval: Int = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Refresh"))
                .font(.headline)
            // No catalog entry for the descriptive subtitle; left as a
            // macOS-only English string for now.
            Text("How often to refresh usage data, in seconds. Must be between 60 and 3600.")
                .font(.callout)
                .foregroundColor(.secondary)

            HStack {
                Text(String(localized: "Poll interval (seconds)"))
                Spacer()
                Stepper(value: $interval, in: 120...3600, step: 30) {
                    Text("\(interval) s")
                        .monospacedDigit()
                        .frame(minWidth: 60, alignment: .trailing)
                }
                .labelsHidden()
                Text("\(interval) s")
                    .monospacedDigit()
                    .frame(minWidth: 60, alignment: .trailing)
            }

            Spacer()
        }
        .padding()
    }
}
