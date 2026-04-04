import SwiftUI

/// Collapsible terminal-style activity log that shows real-time system events.
/// Sits at the bottom of the chat area, above the floating input.
struct ActivityTerminal: View {
    @State private var isExpanded = false
    private var log: ActivityLog { ActivityLog.shared }

    var body: some View {
        VStack(spacing: 0) {
            // Toggle bar
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))

                    Text("Activity")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))

                    if !isExpanded, let last = log.entries.last {
                        Text(last.message)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(last.category.color.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer()

                    if !log.entries.isEmpty {
                        Text("\(log.entries.count)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.05))
                            .clipShape(Capsule())
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded terminal
            if isExpanded {
                Rectangle()
                    .fill(.white.opacity(0.04))
                    .frame(height: 0.5)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(log.entries) { entry in
                                entryRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .frame(height: 140)
                    .onChange(of: log.entries.count) {
                        if let last = log.entries.last {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Clear button
                HStack {
                    Spacer()
                    Button(action: { log.clear() }) {
                        Text("Clear")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                }
            }
        }
        .background(Color(red: 0.067, green: 0.067, blue: 0.067).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
    }

    private func entryRow(_ entry: ActivityEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.timeString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .frame(width: 72, alignment: .leading)

            Image(systemName: entry.category.icon)
                .font(.system(size: 8))
                .foregroundStyle(entry.category.color.opacity(0.6))
                .frame(width: 12)

            Text(entry.message)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        }
        .padding(.vertical, 1)
    }
}
