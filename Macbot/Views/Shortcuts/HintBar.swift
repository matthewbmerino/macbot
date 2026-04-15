import SwiftUI

/// Persistent 22pt footer bar showing the 4–6 most useful keyboard shortcuts
/// for the current mode. Driven by ShortcutRegistry so the copy is never
/// out of sync with the actual bindings.
///
/// The approachability lever: new users see the keyboard-first promise
/// every second, and the keys they need most are always in peripheral
/// vision — mirrors Helix's bottom hint bar.
struct HintBar: View {
    let mode: ContentMode
    var onToggle: () -> Void = {}

    var body: some View {
        HStack(spacing: MacbotDS.Space.md) {
            ForEach(ShortcutRegistry.hintsForMode(mode)) { hint in
                HintChip(hint: hint)
            }
            Spacer()
            Button(action: onToggle) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(MacbotDS.Colors.textTer)
            }
            .buttonStyle(.plain)
            .help("Hide hints (toggle from ⌘/)")
        }
        .padding(.horizontal, MacbotDS.Space.md)
        .padding(.vertical, 4)
        .frame(height: 22)
        .background(.fill.quaternary)
        .overlay(alignment: .top) {
            Divider().opacity(0.6)
        }
    }
}

private struct HintChip: View {
    let hint: ShortcutDef

    var body: some View {
        HStack(spacing: 4) {
            KBDChip(keys: hint.keys)
            Text(hint.label)
                .font(.caption2)
                .foregroundStyle(MacbotDS.Colors.textTer)
        }
    }
}

/// Larger "teach the keyboard" block used inside mode empty states. Shows
/// 3–5 shortcuts with their labels in a friendly column. The approachability
/// moment — first thing a new user sees in any mode.
struct KeyboardTeachBlock: View {
    struct Row { let keys: [String]; let label: String }
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: MacbotDS.Space.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: MacbotDS.Space.sm) {
                    KBDChip(keys: row.keys)
                        .frame(minWidth: 56, alignment: .leading)
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(MacbotDS.Colors.textSec)
                    Spacer()
                }
            }
        }
        .padding(MacbotDS.Space.md)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: MacbotDS.Radius.sm, style: .continuous))
    }
}
