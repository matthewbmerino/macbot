import SwiftUI
import MarkdownUI

struct MessageBubble: View {
    let message: ChatMessage
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: message.role == .user ? "person.circle.fill" : "brain")
                    .font(.caption)
                    .foregroundStyle(message.role == .user ? .primary : Color.accentColor)

                Text(message.role == .user ? "You" : "Macbot")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(message.role == .user ? .primary : Color.accentColor)

                if let agent = message.agentCategory {
                    AgentBadge(category: agent)
                }

                Spacer()

                // Copy button (visible on hover)
                if isHovering && !message.content.isEmpty {
                    Button(action: { copyToClipboard() }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy message")
                    .transition(.opacity)
                }

                Text(message.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }

            // Content
            if !message.content.isEmpty {
                if message.role == .assistant {
                    Markdown(message.content)
                        .markdownTextStyle {
                            FontSize(14)
                        }
                        .markdownBlockStyle(\.codeBlock) { configuration in
                            configuration.label
                                .padding(12)
                                .background(.quaternary.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.quaternary, lineWidth: 1)
                                )
                        }
                        .textSelection(.enabled)
                } else {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }

            // Images
            if let images = message.images, !images.isEmpty {
                imageGrid(images)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    private func imageGrid(_ images: [Data]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 350, maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.top, 4)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
    }
}
