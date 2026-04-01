import Foundation

enum TokenEstimator {
    /// Approximate token count. Words * 1.3 is close enough for Ollama models.
    static func estimate(_ text: String) -> Int {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return Int(Double(words) * 1.3)
    }

    static func estimate(messages: [[String: Any]]) -> Int {
        var total = 0
        for msg in messages {
            if let content = msg["content"] as? String {
                total += estimate(content)
            }
            if let toolCalls = msg["tool_calls"] {
                if let data = try? JSONSerialization.data(withJSONObject: toolCalls),
                   let text = String(data: data, encoding: .utf8) {
                    total += estimate(text)
                }
            }
        }
        return total
    }
}
