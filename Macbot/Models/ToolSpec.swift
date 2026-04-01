import Foundation

struct ToolSpec: Codable {
    let type: String
    let function: ToolFunction

    struct ToolFunction: Codable {
        let name: String
        let description: String
        let parameters: ToolParameters
    }

    struct ToolParameters: Codable {
        let type: String
        let properties: [String: ToolProperty]
        let required: [String]?
    }

    struct ToolProperty: Codable {
        let type: String
        let description: String
    }

    init(name: String, description: String, properties: [String: ToolProperty], required: [String] = []) {
        self.type = "function"
        self.function = ToolFunction(
            name: name,
            description: description,
            parameters: ToolParameters(type: "object", properties: properties, required: required)
        )
    }
}

typealias ToolArguments = [String: Any]
typealias ToolHandler = @Sendable (ToolArguments) async throws -> String
