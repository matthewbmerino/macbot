import SwiftUI

struct MenuBarView: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            // Last message preview
            if let last = viewModel.messages.last(where: { $0.role == .assistant }) {
                Text(String(last.content.prefix(120)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Ready. All processing on-device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Quick input
            HStack(spacing: 8) {
                TextField("Quick message...", text: $viewModel.inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.send() }
                    .disabled(viewModel.isStreaming)

                if viewModel.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Divider()

            // Actions
            HStack {
                Button("Open Window") {
                    openWindow(id: "main")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Spacer()

                Text(viewModel.activeAgent.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
