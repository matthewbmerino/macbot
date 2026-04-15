import AppKit

/// App-wide focus probe used by keyboard-shortcut handlers to decide whether
/// an unmodified single-key shortcut should fire or pass through to an
/// editor / field. Lifts the pattern CanvasScrollHandler already uses so
/// chat and notebook can reach for the same rule.
enum AppFocus {
    /// True if the key window's current first responder is an *editable*
    /// text input. Read-only text views (MarkdownUI's NSTextView,
    /// `.textSelection(.enabled)` labels) don't count.
    static func isTextInputActive() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable
        }
        return false
    }
}
