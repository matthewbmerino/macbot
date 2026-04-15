import SwiftUI

/// Single source of truth for every user-facing keyboard shortcut in the app.
/// Drives the global ⌘/ cheat sheet, the footer hint bar, and the chips shown
/// next to actions in the command palette. Shortcuts are declarative data, not
/// a pile of handler-site calls — so a new binding only has to be authored
/// here once for the rest of the UI to reflect it.
///
/// ## Esc cascade contract
///
/// Pressing Escape in any mode unwinds state from most-modal to least-modal.
/// Handlers should early-return on the first step that has something to do:
///
///   1. Top-most overlay (cheat sheet / command palette) — dismisses itself.
///   2. Focused text input (composer / editor / rename field) — blurs so
///      the mode's list-nav keys (`↑/↓/j/k/n`) become available.
///   3. In-mode transient state — canvas exits 3D / edge / AI bar / help /
///      inline chat; chat stops streaming; notebook cancels rename.
///   4. Selection or search — clears.
///
/// Rule: never consume Esc at step N if step >N has state to unwind, and never
/// skip step 2 — a stuck-focused editor is the single worst keyboard-app
/// failure mode.
enum ShortcutScope {
    case global
    case chat
    case canvas
    case notebook
    case palette
}

enum ShortcutCategory: Int, CaseIterable {
    case navigation = 0
    case create     = 1
    case edit       = 2
    case view       = 3
    case ai         = 4
    case help       = 5

    var label: String {
        switch self {
        case .navigation: return "Navigation"
        case .create:     return "Create"
        case .edit:       return "Edit"
        case .view:       return "View"
        case .ai:         return "AI"
        case .help:       return "Help"
        }
    }
}

struct ShortcutDef: Identifiable {
    let id = UUID()
    /// Display chips in order, e.g. ["⌘", "N"] or ["⇧", "⇥"] or ["?"].
    let keys: [String]
    let label: String
    let scope: ShortcutScope
    let category: ShortcutCategory
    /// Optional longer context, shown in the cheat sheet only.
    let detail: String?

    init(_ keys: [String], _ label: String, scope: ShortcutScope, category: ShortcutCategory, detail: String? = nil) {
        self.keys = keys
        self.label = label
        self.scope = scope
        self.category = category
        self.detail = detail
    }

    /// Flat display string used by the palette chip, e.g. "⌘N".
    var chipString: String { keys.joined() }
}

enum ShortcutRegistry {
    // MARK: - Canonical list

    static let all: [ShortcutDef] = [
        // Global
        ShortcutDef(["⌘", "K"],       "Command palette",     scope: .global, category: .navigation),
        ShortcutDef(["⌘", "/"],       "Keyboard cheat sheet", scope: .global, category: .help),
        ShortcutDef(["⌘", "1"],       "Notebook mode",       scope: .global, category: .navigation),
        ShortcutDef(["⌘", "2"],       "Canvas mode",         scope: .global, category: .navigation),
        ShortcutDef(["⌘", "3"],       "Chat mode",           scope: .global, category: .navigation),
        ShortcutDef(["⌘", "\\"],      "Toggle sidebar",      scope: .global, category: .view),
        ShortcutDef(["⌘", "N"],       "New in this mode",    scope: .global, category: .create,
                    detail: "New chat / canvas / page depending on current mode."),
        ShortcutDef(["⎋"],            "Back / dismiss",      scope: .global, category: .navigation),

        // Canvas
        ShortcutDef(["N"],                    "New card",             scope: .canvas, category: .create,
                    detail: "Creates a new note card. Cycle color with ⇧⇥ if you want to flag it as task/idea."),
        ShortcutDef(["/"],                    "Ask AI",               scope: .canvas, category: .ai),
        ShortcutDef(["⌘", "↩"],               "Execute selected",     scope: .canvas, category: .ai),
        ShortcutDef(["E"],                    "Edge mode",            scope: .canvas, category: .edit),
        ShortcutDef(["M"],                    "Toggle minimap",       scope: .canvas, category: .view),
        ShortcutDef(["⇥"],                    "Next card",            scope: .canvas, category: .navigation),
        ShortcutDef(["⇧", "⇥"],               "Cycle card color",     scope: .canvas, category: .edit),
        ShortcutDef(["←", "↑", "↓", "→"],     "Spatial navigation",   scope: .canvas, category: .navigation),
        ShortcutDef(["⌫"],                    "Delete selected",      scope: .canvas, category: .edit),
        ShortcutDef(["⌘", "A"],               "Select all",           scope: .canvas, category: .edit),
        ShortcutDef(["⌘", "G"],               "Group selected",       scope: .canvas, category: .edit),
        ShortcutDef(["⌘", "D"],               "Duplicate",            scope: .canvas, category: .edit),
        ShortcutDef(["⌘", "C"],               "Copy",                 scope: .canvas, category: .edit),
        ShortcutDef(["⌘", "V"],               "Paste",                scope: .canvas, category: .edit),
        ShortcutDef(["⌘", "X"],               "Cut",                  scope: .canvas, category: .edit),
        ShortcutDef(["⌘", "Z"],               "Undo",                 scope: .canvas, category: .edit),
        ShortcutDef(["⌘", "⇧", "Z"],          "Redo",                 scope: .canvas, category: .edit),
        ShortcutDef(["⌘", "0"],               "Reset zoom",           scope: .canvas, category: .view),
        ShortcutDef(["⌘", "1"],               "Zoom to fit",          scope: .canvas, category: .view),
        ShortcutDef(["⌘", "2"],               "Zoom to selection",    scope: .canvas, category: .view),
        ShortcutDef(["+", "="],               "Zoom in",              scope: .canvas, category: .view),
        ShortcutDef(["−"],                    "Zoom out",             scope: .canvas, category: .view),
        ShortcutDef(["Space", "+", "drag"],   "Pan canvas",           scope: .canvas, category: .navigation),
        ShortcutDef(["⌘", "⇧", "F"],          "Search canvases",      scope: .canvas, category: .navigation),
        ShortcutDef(["↩"],                    "Done editing card",    scope: .canvas, category: .edit,
                    detail: "Commit the typed text and leave edit mode. No AI runs."),
        ShortcutDef(["⌘", "↩"],               "Ask AI (expand card)", scope: .canvas, category: .ai,
                    detail: "Commit and expand into a knowledge graph. The AI key."),
        ShortcutDef(["⇧", "↩"],               "Newline while editing", scope: .canvas, category: .edit),
        ShortcutDef(["⎋"],                    "Done editing card",    scope: .canvas, category: .edit,
                    detail: "Same as ↩ — commit and leave edit mode."),

        // Chat
        ShortcutDef(["↩"],                "Send message",       scope: .chat, category: .ai),
        ShortcutDef(["⎋"],                "Stop streaming",     scope: .chat, category: .ai),

        // Notebook (Wave 2 will expand)
        ShortcutDef(["⎋"],                "Cancel rename",      scope: .notebook, category: .edit),

        // Palette
        ShortcutDef(["↑", "↓"],           "Navigate results",   scope: .palette, category: .navigation),
        ShortcutDef(["↩"],                "Open selected",      scope: .palette, category: .navigation),
        ShortcutDef(["⎋"],                "Dismiss",            scope: .palette, category: .navigation),
    ]

    // MARK: - Queries

    /// All shortcuts visible in a given mode: always includes `.global`,
    /// plus the mode-specific scope.
    static func forMode(_ mode: ContentMode) -> [ShortcutDef] {
        let modeScope: ShortcutScope = {
            switch mode {
            case .chat:     return .chat
            case .canvas:   return .canvas
            case .notebook: return .notebook
            }
        }()
        return all.filter { $0.scope == .global || $0.scope == modeScope }
    }

    /// The 4–6 keys to surface in the persistent footer hint bar. Hand-picked
    /// so a user glancing at the footer sees the most high-value keys for
    /// their current context, not a firehose.
    static func hintsForMode(_ mode: ContentMode) -> [ShortcutDef] {
        switch mode {
        case .canvas:
            return pick([
                (["N"], "new card"),
                (["/"], "AI"),
                (["⇥"], "next"),
                (["⇧", "⇥"], "color"),
                (["⌘", "N"], "new canvas"),
                (["⌘", "/"], "all keys"),
            ])
        case .chat:
            return pick([
                (["⌘", "N"], "new chat"),
                (["⌘", "K"], "palette"),
                (["↩"], "send"),
                (["⌘", "/"], "all keys"),
            ])
        case .notebook:
            return pick([
                (["⌘", "N"], "new page"),
                (["⌘", "K"], "palette"),
                (["⌘", "/"], "all keys"),
            ])
        }
    }

    // MARK: - Private

    /// Small helper so the hint bar list reads as (keys, label) tuples.
    private static func pick(_ pairs: [(keys: [String], label: String)]) -> [ShortcutDef] {
        pairs.map { ShortcutDef($0.keys, $0.label, scope: .global, category: .navigation) }
    }
}
