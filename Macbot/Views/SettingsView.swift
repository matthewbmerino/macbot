import SwiftUI

struct SettingsView: View {
    @AppStorage("ollamaHost") private var ollamaHost = "http://localhost:11434"
    @AppStorage("generalModel") private var generalModel = "qwen3.5:9b"
    @AppStorage("coderModel") private var coderModel = "devstral-small-2"
    @AppStorage("visionModel") private var visionModel = "qwen3-vl:8b"
    @AppStorage("reasonerModel") private var reasonerModel = "deepseek-r1:14b"
    @AppStorage("routerModel") private var routerModel = "qwen3.5:0.8b"

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            modelsTab
                .tabItem { Label("Models", systemImage: "cpu") }
        }
        .frame(width: 450, height: 300)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Section("Ollama Connection") {
                TextField("Host", text: $ollamaHost)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var modelsTab: some View {
        Form {
            Section("Model Assignments") {
                LabeledContent("General") {
                    TextField("Model", text: $generalModel).textFieldStyle(.roundedBorder)
                }
                LabeledContent("Coder") {
                    TextField("Model", text: $coderModel).textFieldStyle(.roundedBorder)
                }
                LabeledContent("Vision") {
                    TextField("Model", text: $visionModel).textFieldStyle(.roundedBorder)
                }
                LabeledContent("Reasoner") {
                    TextField("Model", text: $reasonerModel).textFieldStyle(.roundedBorder)
                }
                LabeledContent("Router") {
                    TextField("Model", text: $routerModel).textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}
