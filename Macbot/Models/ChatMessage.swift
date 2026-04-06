import Foundation

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

struct ChatMessage: Identifiable {
    let id: UUID
    var role: MessageRole
    var content: String
    var images: [Data]?
    var toolCalls: [[String: Any]]?
    var agentCategory: AgentCategory?
    var timestamp: Date

    // Response metrics (assistant messages only)
    var responseTime: TimeInterval?  // Total time from send to complete
    var tokenCount: Int?             // Estimated tokens in response
    var tokensPerSecond: Double?     // Generation speed
    var modelName: String?           // The actual model that produced this response

    init(
        role: MessageRole,
        content: String,
        images: [Data]? = nil,
        toolCalls: [[String: Any]]? = nil,
        agentCategory: AgentCategory? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.images = images
        self.toolCalls = toolCalls
        self.agentCategory = agentCategory
        self.timestamp = Date()
    }

    /// Formatted metrics string for display (e.g., "1m 23s · 847 tokens · 42 tok/s")
    var metricsString: String? {
        guard role == .assistant, let time = responseTime, time > 0 else { return nil }

        var parts: [String] = []

        // Time
        if time >= 60 {
            let minutes = Int(time) / 60
            let seconds = Int(time) % 60
            parts.append("\(minutes)m \(seconds)s")
        } else {
            parts.append(String(format: "%.1fs", time))
        }

        // Tokens
        if let tokens = tokenCount, tokens > 0 {
            parts.append("\(tokens) tokens")
        }

        // Speed
        if let tps = tokensPerSecond, tps > 0 {
            parts.append(String(format: "%.0f tok/s", tps))
        }

        // Model
        if let model = modelName, !model.isEmpty {
            parts.append(model)
        }

        return parts.joined(separator: " · ")
    }

    /// Convert to Ollama API message format.
    var asOllamaDict: [String: Any] {
        var dict: [String: Any] = ["role": role.rawValue, "content": content]
        if let images {
            dict["images"] = images.map { $0.base64EncodedString() }
        }
        if let toolCalls {
            dict["tool_calls"] = toolCalls
        }
        return dict
    }
}
