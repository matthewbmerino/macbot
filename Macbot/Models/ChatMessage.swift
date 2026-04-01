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
