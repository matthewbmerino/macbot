import SwiftUI
import MarkdownUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 6) {
                Text(message.role == .user ? "You" : "Macbot")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(message.role == .user ? .primary : Color.accentColor)

                if let agent = message.agentCategory {
                    Text(agent.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                Spacer()

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Content
            if message.role == .assistant {
                Markdown(message.content)
                    .markdownTextStyle {
                        FontSize(14)
                    }
            } else {
                Text(message.content)
                    .font(.body)
            }

            // Images
            if let images = message.images {
                ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
