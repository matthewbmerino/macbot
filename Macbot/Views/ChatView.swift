import SwiftUI
import MarkdownUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 16) {
                Text("Macbot")
                    .font(.headline)
                    .padding(.horizontal)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Agent: \(viewModel.activeAgent.displayName)", systemImage: "cpu")
                    Label("\(viewModel.messages.count) messages", systemImage: "bubble.left.and.bubble.right")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                Spacer()

                Button(action: { viewModel.clearConversation() }) {
                    Label("Clear Conversation", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .padding(.top, 12)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            if let status = viewModel.currentStatus {
                                StatusIndicator(text: status)
                                    .id("status")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) {
                        withAnimation {
                            if let lastId = viewModel.messages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input bar
                HStack(spacing: 10) {
                    TextField("Message macbot...", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .focused($inputFocused)
                        .onSubmit { sendMessage() }
                        .disabled(viewModel.isStreaming)

                    Button(action: { sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? .secondary : Color.accentColor
                            )
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isStreaming)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 600, minHeight: 450)
        .onAppear { inputFocused = true }
    }

    private func sendMessage() {
        viewModel.send()
        inputFocused = true
    }
}

struct AgentBadge: View {
    let category: AgentCategory

    var body: some View {
        Text(category.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}
