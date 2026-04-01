import Foundation

final class VisionAgent: BaseAgent {
    init(client: any InferenceProvider, model: String = "qwen3-vl:8b") {
        super.init(
            name: "vision",
            model: model,
            systemPrompt: "You are a vision AI assistant. Analyze images thoroughly and describe what you see in detail. Extract text, identify objects, and explain visual content.",
            temperature: 0.5,
            numCtx: 16384,
            client: client
        )
    }
}
