import Foundation

final class Router {
    private let client: any InferenceProvider
    private let model: String

    private static let routerPrompt = """
    You are a task router. Classify the user's message into exactly one category.
    Respond with ONLY a JSON object, no other text.

    Categories:
    - "coder": programming, code generation, debugging, code review, technical implementation
    - "vision": the user is sending an image for you to analyze (this is handled automatically, rarely pick this)
    - "reasoner": math, logic puzzles, complex analysis, step-by-step problem solving
    - "rag": questions about documents, knowledge base queries, "what does the doc say"
    - "general": conversation, planning, writing, summarization, web browsing, taking screenshots, research tasks, and everything else

    IMPORTANT: If the user asks you to browse a website, take a screenshot, or do web research, classify as "general" NOT "vision".

    Format: {"category": "<category>", "reason": "<brief reason>"}
    """

    init(client: any InferenceProvider, model: String = "qwen3.5:0.8b") {
        self.client = client
        self.model = model
    }

    func classify(message: String, hasImages: Bool = false) async -> AgentCategory {
        if hasImages { return .vision }

        do {
            let resp = try await client.chat(
                model: model,
                messages: [
                    ["role": "system", "content": Self.routerPrompt],
                    ["role": "user", "content": message],
                ],
                tools: nil,
                temperature: 0.1,
                numCtx: 2048,
                timeout: 15
            )

            let content = ThinkingStripper.strip(resp.content)

            guard let data = content.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let categoryStr = json["category"],
                  let category = AgentCategory(rawValue: categoryStr)
            else {
                Log.agents.warning("[router] failed to parse: \(content), defaulting to general")
                return .general
            }

            Log.agents.info("[router] classified as '\(categoryStr)': \(json["reason"] ?? "")")
            return category
        } catch {
            Log.agents.warning("[router] error: \(error), defaulting to general")
            return .general
        }
    }
}
