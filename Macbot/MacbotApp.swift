import SwiftUI
import AppKit

@main
struct MacbotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Macbot", systemImage: "brain") {
            if appState.isReady {
                MenuBarView(viewModel: appState.chatViewModel!)
            } else {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting...").font(.caption)
                }
                .padding()
            }
        }
        .menuBarExtraStyle(.window)

        Window("Macbot", id: "main") {
            Group {
                if !appState.isReady {
                    OnboardingView(client: appState.orchestrator.client) {
                        Task { await appState.initialize() }
                    }
                } else {
                    ChatView(viewModel: appState.chatViewModel!)
                }
            }
            .onAppear {
                // Activate the app so the window comes to front and accepts input
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy to regular so the app gets a dock icon and proper window behavior
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Reopen main window when dock icon is clicked
            for window in sender.windows {
                if window.title == "Macbot" {
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
            }
        }
        return true
    }
}

@Observable
final class AppState {
    let orchestrator = Orchestrator()
    var chatViewModel: ChatViewModel?
    var isReady = false

    init() {
        Task { await initialize() }
    }

    func initialize() async {
        let reachable = await orchestrator.client.isReachable()
        if reachable {
            let vm = ChatViewModel(orchestrator: orchestrator)
            await MainActor.run {
                self.chatViewModel = vm
                self.isReady = true
            }
            Log.app.info("Macbot ready")

            Task.detached(priority: .background) { [orchestrator] in
                await orchestrator.prewarm()
            }
        }
    }
}
