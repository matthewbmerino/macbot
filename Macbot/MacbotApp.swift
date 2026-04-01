import SwiftUI

@main
struct MacbotApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Macbot", systemImage: "brain") {
            if let vm = appState.chatViewModel {
                MenuBarView(viewModel: vm)
            } else {
                Text("Connecting...").padding()
            }
        }
        .menuBarExtraStyle(.window)

        Window("Macbot", id: "main") {
            if let vm = appState.chatViewModel {
                ChatView(viewModel: vm)
            } else {
                ProgressView("Connecting to Ollama...")
                    .frame(width: 300, height: 200)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

@Observable
final class AppState {
    var orchestrator: Orchestrator
    var chatViewModel: ChatViewModel?

    init() {
        self.orchestrator = Orchestrator()
        Task {
            await orchestrator.prewarm()
            await MainActor.run {
                self.chatViewModel = ChatViewModel(orchestrator: orchestrator)
            }
            Log.app.info("Macbot ready")
        }
    }
}
