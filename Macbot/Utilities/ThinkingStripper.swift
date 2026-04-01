import Foundation

enum ThinkingStripper {
    /// Remove <think>...</think> blocks from model output.
    static func strip(_ text: String) -> String {
        guard text.contains("<think>") || text.contains("</think>") else {
            return text
        }

        var result = text

        // Remove complete thinking blocks
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: []) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: ""
            )
        }

        // Handle unclosed thinking tag
        if let range = result.range(of: "<think>") {
            result = String(result[result.startIndex..<range.lowerBound])
        }

        // Handle orphaned closing tag
        if let range = result.range(of: "</think>") {
            result = String(result[range.upperBound...])
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
