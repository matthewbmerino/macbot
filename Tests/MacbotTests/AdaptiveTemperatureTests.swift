import XCTest
@testable import Macbot

/// Locks the contract for the anti-hallucination temperature adaptation:
/// once any tool has been called this turn we have grounded data the model
/// should be quoting verbatim, so creative sampling buys nothing and risks
/// the model "smoothing" numbers. The clamp must be a strict minimum.
final class AdaptiveTemperatureTests: XCTestCase {

    private func makeAgent(temperature: Double) -> BaseAgent {
        BaseAgent(
            name: "test",
            model: "m",
            systemPrompt: "test",
            temperature: temperature,
            numCtx: 4096,
            client: MockInferenceProvider()
        )
    }

    func testNoToolsKeepsConfiguredTemperature() {
        XCTAssertEqual(makeAgent(temperature: 0.7).adaptiveTemperature(toolCallCount: 0), 0.7)
        XCTAssertEqual(makeAgent(temperature: 0.4).adaptiveTemperature(toolCallCount: 0), 0.4)
    }

    func testWithToolsClampsToTwoTenths() {
        // High-temperature general agent should drop hard
        XCTAssertEqual(makeAgent(temperature: 0.7).adaptiveTemperature(toolCallCount: 1), 0.2)
        XCTAssertEqual(makeAgent(temperature: 0.5).adaptiveTemperature(toolCallCount: 3), 0.2)
    }

    func testAlreadyColdAgentStaysCold() {
        // A reasoner-style agent already configured below 0.2 must not be
        // raised — the clamp is min(), not a fixed value.
        XCTAssertEqual(makeAgent(temperature: 0.1).adaptiveTemperature(toolCallCount: 5), 0.1)
        XCTAssertEqual(makeAgent(temperature: 0.0).adaptiveTemperature(toolCallCount: 1), 0.0)
    }

    func testAntiFabricationClauseIsAppendedToSystemPrompt() {
        let agent = makeAgent(temperature: 0.7)
        XCTAssertTrue(agent.systemPrompt.contains("GROUNDING"),
                      "every agent must inherit the anti-fabrication clause")
        XCTAssertTrue(agent.systemPrompt.contains("I don't have that"),
                      "the explicit refusal phrasing must be present")
        XCTAssertTrue(agent.systemPrompt.contains("verbatim"),
                      "the verbatim-quoting rule must be present for tool grounding")
    }
}
