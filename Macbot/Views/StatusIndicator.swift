import SwiftUI

struct StatusIndicator: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(.vertical, 4)
    }
}
