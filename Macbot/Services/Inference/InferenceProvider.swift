import Foundation

struct ChatResponse {
    let content: String
    let toolCalls: [[String: Any]]?
}

struct ModelInfo {
    let name: String
    let size: Int64?
}

protocol InferenceProvider: Sendable {
    func chat(
        model: String,
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        temperature: Double,
        numCtx: Int,
        timeout: TimeInterval?
    ) async throws -> ChatResponse

    func chatStream(
        model: String,
        messages: [[String: Any]],
        temperature: Double,
        numCtx: Int
    ) -> AsyncThrowingStream<String, Error>

    func embed(model: String, text: [String]) async throws -> [[Float]]
    func listModels() async throws -> [ModelInfo]
    func warmModel(_ model: String) async throws
}
