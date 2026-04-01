import Foundation

final class CoderAgent: BaseAgent {
    init(client: any InferenceProvider, model: String = "devstral-small-2") {
        super.init(
            name: "coder",
            model: model,
            systemPrompt: "You are an expert software engineer. Write clean, working code. Explain your approach briefly. Use tools to read files, run code, and verify your work.",
            temperature: 0.4,
            numCtx: 65536,
            client: client
        )
    }
}
