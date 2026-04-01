import Foundation

final class ReasonerAgent: BaseAgent {
    init(client: any InferenceProvider, model: String = "deepseek-r1:14b") {
        super.init(
            name: "reasoner",
            model: model,
            systemPrompt: "You are an expert at mathematical reasoning, logic, and step-by-step analysis. Show your work clearly. Break complex problems into manageable steps.",
            temperature: 0.3,
            numCtx: 32768,
            client: client
        )
    }
}
