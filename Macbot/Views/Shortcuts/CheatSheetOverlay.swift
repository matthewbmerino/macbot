import SwiftUI

/// Global keyboard cheat sheet. Invoked via ⌘/ in any mode — replaces the
/// canvas-only `?` overlay so every mode gets one discoverable help surface.
/// Groups shortcuts into Global | Current Mode columns by category so a
/// learner sees the shape of the keymap, not just a flat list.
struct CheatSheetOverlay: View {
    let mode: ContentMode
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            sheet
                .frame(maxWidth: 820, maxHeight: 640)
                .background(MacbotDS.Mat.chrome)
                .clipShape(RoundedRectangle(cornerRadius: MacbotDS.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacbotDS.Radius.lg, style: .continuous)
                        .stroke(MacbotDS.Colors.separator.opacity(0.6), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 32, y: 12)
        }
        .onExitCommand { onDismiss() }
    }

    // MARK: - Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                HStack(alignment: .top, spacing: MacbotDS.Space.xl) {
                    column(title: "Global",     scope: .global)
                    column(title: modeTitle,    scope: modeScope)
                }
                .padding(MacbotDS.Space.xl)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Keyboard shortcuts")
                .font(MacbotDS.Typo.title)
                .foregroundStyle(MacbotDS.Colors.textPri)
            Spacer()
            KBDChip(keys: ["⌘", "/"])
                .opacity(0.7)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(MacbotDS.Colors.textTer)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, MacbotDS.Space.lg)
        .padding(.vertical, MacbotDS.Space.md)
    }

    // MARK: - Columns

    private var modeScope: ShortcutScope {
        switch mode {
        case .chat:     return .chat
        case .canvas:   return .canvas
        case .notebook: return .notebook
        }
    }

    private var modeTitle: String {
        switch mode {
        case .chat:     return "Chat"
        case .canvas:   return "Canvas"
        case .notebook: return "Notebook"
        }
    }

    private func column(title: String, scope: ShortcutScope) -> some View {
        let entries = ShortcutRegistry.all.filter { $0.scope == scope }
        let byCategory = Dictionary(grouping: entries, by: { $0.category })
        return VStack(alignment: .leading, spacing: MacbotDS.Space.lg) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .kerning(0.5)
                .foregroundStyle(MacbotDS.Colors.textTer)

            ForEach(ShortcutCategory.allCases, id: \.self) { category in
                if let items = byCategory[category], !items.isEmpty {
                    categorySection(category, items: items)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categorySection(_ category: ShortcutCategory, items: [ShortcutDef]) -> some View {
        VStack(alignment: .leading, spacing: MacbotDS.Space.xs) {
            Text(category.label)
                .font(MacbotDS.Typo.heading)
                .foregroundStyle(MacbotDS.Colors.textPri)
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: MacbotDS.Space.sm) {
                    KBDChip(keys: item.keys)
                        .frame(minWidth: 96, alignment: .trailing)
                    Text(item.label)
                        .font(.system(size: 12))
                        .foregroundStyle(MacbotDS.Colors.textSec)
                    Spacer()
                }
            }
        }
    }
}

/// Monospaced keycap chip used everywhere a shortcut is displayed — cheat
/// sheet, hint bar, palette row. One component, one look.
struct KBDChip: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MacbotDS.Colors.textSec)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .frame(minWidth: 18)
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
        }
    }
}
