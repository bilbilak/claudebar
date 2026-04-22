import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    convenience init() {
        let hosting = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "ClaudeBar"
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
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            DisplayPane()
                .tabItem { Label("Display", systemImage: "paintbrush") }
            AdvancedPane()
                .tabItem { Label("Advanced", systemImage: "gearshape") }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 400)
    }
}

// MARK: - Account

struct AccountPane: View {
    @State private var status: String = "Checking…"
    @State private var signedIn: Bool = false
    @State private var inProgress: Bool = false
    @State private var errorMessage: String?
    @State private var currentLogin: OAuth.LoginFlow?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Authentication")
                .font(.headline)
            Text("Sign in with your Claude account to fetch Max-plan usage. Tokens are encrypted at rest in the macOS Keychain.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text("Status:")
                Text(status).foregroundColor(.secondary)
                Spacer()
                if signedIn {
                    Button("Sign out") { signOut() }
                        .disabled(inProgress)
                } else {
                    Button("Sign in with Claude") { signIn() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(inProgress)
                }
            }

            if inProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for browser sign-in…")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel") { cancel() }
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
            status = "Signed in (token ends ‘…\(tail)’)"
            signedIn = true
        } else {
            status = "Not signed in"
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
            Text("Menu bar")
                .font(.headline)
            Toggle("Show numeric percentages next to bars", isOn: $showPercentages)
                .toggleStyle(.switch)
            Text("Small session and weekly percentages, stacked beside the bars.")
                .font(.callout)
                .foregroundColor(.secondary)

            Divider()

            Text("Color thresholds")
                .font(.headline)
            Text("When the bars switch from green to orange to red.")
                .font(.callout)
                .foregroundColor(.secondary)

            stepperRow(title: "Orange at", value: $warn)
            stepperRow(title: "Red at", value: $crit)

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
            Text("Refresh")
                .font(.headline)
            Text("How often to refresh usage data, in seconds. Must be between 60 and 3600.")
                .font(.callout)
                .foregroundColor(.secondary)

            HStack {
                Text("Poll interval")
                Spacer()
                Stepper(value: $interval, in: 60...3600, step: 30) {
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
