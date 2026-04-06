import XCTest
@testable import Macbot

/// Locks the contract for the conversation-level shared transcript that
/// keeps context coherent across routing changes. The bug this prevents:
/// turn 1 routes to general, turn 2 routes to a different agent, turn 3
/// routes to a third — and the user reports "the model lost context after
/// one message" because each agent only saw its own per-instance history.
final class SharedTranscriptTests: XCTestCase {

    private func makeAgent(prompt: String = "you are agent A") -> BaseAgent {
        BaseAgent(
            name: "test",
            model: "m",
            systemPrompt: prompt,
            temperature: 0.5,
            numCtx: 4096,
            client: MockInferenceProvider()
        )
    }

    func testLoadHistoryFromTranscriptStartsWithSystemPromptThenTranscript() {
        let agent = makeAgent()
        let transcript: [[String: Any]] = [
            ["role": "user", "content": "hi"],
            ["role": "assistant", "content": "hello"],
            ["role": "user", "content": "what's the weather?"],
        ]
        agent.loadHistoryFromTranscript(transcript)

        XCTAssertEqual(agent.history.count, 4)
        XCTAssertEqual(agent.history[0]["role"] as? String, "system")
        XCTAssertTrue((agent.history[0]["content"] as? String ?? "").contains("you are agent A"))
        XCTAssertEqual(agent.history[1]["content"] as? String, "hi")
        XCTAssertEqual(agent.history[3]["content"] as? String, "what's the weather?")
    }

    func testLoadHistoryFromEmptyTranscriptJustHasSystemPrompt() {
        let agent = makeAgent()
        agent.loadHistoryFromTranscript([])
        XCTAssertEqual(agent.history.count, 1)
        XCTAssertEqual(agent.history[0]["role"] as? String, "system")
    }

    func testLoadHistoryReplacesPreviousState() {
        let agent = makeAgent()
        // Simulate prior turn cruft
        agent.loadHistoryFromTranscript([
            ["role": "user", "content": "old turn"],
            ["role": "assistant", "content": "old response"],
        ])
        // New turn arrives — replace, not append
        agent.loadHistoryFromTranscript([
            ["role": "user", "content": "new turn"],
        ])
        XCTAssertEqual(agent.history.count, 2)
        XCTAssertEqual(agent.history[1]["content"] as? String, "new turn")
    }

    /// Simulates the actual fix: routing across two agents in the same
    /// conversation. Agent B should see what the user said to agent A.
    func testCrossAgentContinuity() {
        let agentA = makeAgent(prompt: "you are A")
        let agentB = makeAgent(prompt: "you are B")

        // Conversation transcript starts empty
        var transcript: [[String: Any]] = []

        // Turn 1: A handles a question and answers
        agentA.loadHistoryFromTranscript(transcript)
        agentA.history.append(["role": "user", "content": "what's the weather in nassau?"])
        agentA.history.append(["role": "assistant", "content": "75 and sunny"])
        // Capture (skip system, append user-visible)
        for msg in agentA.history.dropFirst() where (msg["role"] as? String) != "system" {
            transcript.append(msg)
        }

        // Turn 2: B handles a follow-up
        agentB.loadHistoryFromTranscript(transcript)
        // B now sees the original question + A's answer in its history
        XCTAssertEqual(agentB.history.count, 3)  // system + user + assistant
        XCTAssertEqual(agentB.history[1]["content"] as? String, "what's the weather in nassau?")
        XCTAssertEqual(agentB.history[2]["content"] as? String, "75 and sunny")
        // And B's own system prompt is at the top
        XCTAssertTrue((agentB.history[0]["content"] as? String ?? "").contains("you are B"))
    }
}
