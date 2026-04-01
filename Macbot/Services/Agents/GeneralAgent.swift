import Foundation

final class GeneralAgent: BaseAgent {
    init(client: any InferenceProvider, model: String = "qwen3.5:9b") {
        super.init(
            name: "general",
            model: model,
            systemPrompt: "You are a capable AI assistant. Answer concisely and accurately. Use tools when they help answer the question.",
            temperature: 0.7,
            numCtx: 32768,
            client: client
        )
    }
}
