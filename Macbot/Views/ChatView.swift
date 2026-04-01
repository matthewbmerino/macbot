import SwiftUI
import MarkdownUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
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
                .onChange(of: viewModel.currentStatus) { _, _ in
                    withAnimation {
                        proxy.scrollTo("status", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 10) {
                TextField("Message macbot...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit { viewModel.send() }
                    .disabled(viewModel.isStreaming)

                Button(action: { viewModel.send() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.inputText.isEmpty ? .secondary : Color.accentColor)
                }
                .disabled(viewModel.inputText.isEmpty || viewModel.isStreaming)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 500, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                AgentBadge(category: viewModel.activeAgent)
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { viewModel.clearConversation() }) {
                    Image(systemName: "trash")
                }
                .help("Clear conversation")
            }
        }
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
