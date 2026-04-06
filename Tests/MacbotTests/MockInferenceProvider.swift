import Foundation
@testable import Macbot

/// Test double for `InferenceProvider` that produces deterministic, content-aware
/// embeddings without ever talking to Ollama.
///
/// Embeddings are 8-dim category-biased vectors. The first 5 dimensions correspond
/// to the agent categories in the order [general, coder, vision, reasoner, rag].
/// For each input text we count keyword hits per category and write them into the
/// corresponding dimension. This is enough to make the cosine-similarity router
/// classify correctly in tests, while remaining trivial and offline.
final class MockInferenceProvider: InferenceProvider, @unchecked Sendable {

    /// Per-call recordings for assertions.
    var embedCalls: [(model: String, text: [String])] = []
    var chatCalls: Int = 0

    /// If non-nil, embed() throws this error instead of returning vectors.
    var embedError: Error?

    /// Optional override: if set, returns these vectors instead of synthesizing.
    var embedOverride: [[Float]]?

    private static let categoryKeywords: [(category: Int, words: [String])] = [
        // 0: general
        (0, ["weather", "news", "plan", "email", "trip", "remind", "meeting", "open the calculator", "documents folder", "team about"]),
        // 1: coder
        (1, ["python", "function", "bug", "swift", "dockerfile", "rest api", "refactor", "segmentation", "unit test", "sql query", "async await", "regex pattern", "code"]),
        // 2: vision
        (2, ["image", "screenshot", "photo", "picture", "see in this", "chart image", "logo", "color scheme", "ui mockup", "describe", "graph"]),
        // 3: reasoner
        (3, ["derivative", "equation", "prove", "probability", "irrational", "complexity", "optimization", "expected value", "induction", "logic behind", "calculate"]),
        // 4: rag
        (4, ["documentation", "find the relevant", "my notes", "report say", "api specification", "database schema", "policy", "knowledge base", "migration plan", "design document"]),
    ]

    func chat(
        model: String,
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        temperature: Double,
        numCtx: Int,
        timeout: TimeInterval?
    ) async throws -> ChatResponse {
        chatCalls += 1
        return ChatResponse(content: "mock response", toolCalls: nil)
    }

    func chatStream(
        model: String,
        messages: [[String: Any]],
        temperature: Double,
        numCtx: Int
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("mock")
            continuation.finish()
        }
    }

    func embed(model: String, text: [String]) async throws -> [[Float]] {
        embedCalls.append((model, text))
        if let embedError { throw embedError }
        if let embedOverride { return embedOverride }
        return text.map { Self.embedding(for: $0) }
    }

    func listModels() async throws -> [ModelInfo] { [] }
    func warmModel(_ model: String) async throws {}

    // MARK: - Embedding synthesis

    static func embedding(for text: String) -> [Float] {
        var vec = [Float](repeating: 0.05, count: 8)  // small noise floor
        let lower = text.lowercased()
        for entry in categoryKeywords {
            for word in entry.words where lower.contains(word) {
                vec[entry.category] += 1.0
            }
        }
        // Tiny tail differentiator so distinct strings hash slightly differently.
        vec[5] = Float(text.count % 7) * 0.01
        vec[6] = Float(text.count % 11) * 0.01
        vec[7] = Float(text.count % 13) * 0.01
        return vec
    }
}
