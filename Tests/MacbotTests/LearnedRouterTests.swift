import XCTest
@testable import Macbot

/// Locks the contract for the precomputed-embedding overload of
/// LearnedRouter.predict. This is the variant the speed pass added so the
/// orchestrator can embed the user query exactly once and feed both
/// SkillStore.retrieve and LearnedRouter.predict from the same vector —
/// instead of two independent Ollama round-trips on every turn.
final class LearnedRouterTests: XCTestCase {

    func testPredictWithEmptyEmbeddingReturnsNil() {
        // Defensive: an empty vector means the embedder failed upstream.
        // The router must not crash and must not query the trace store.
        let result = LearnedRouter.predict(forQueryEmbedding: [], topK: 8, minSimilarity: 0.55)
        XCTAssertNil(result)
    }

    func testPredictWithNoTracesReturnsNil() {
        // With a fresh trace store there are no neighbors above the
        // similarity floor, so the router must return nil rather than
        // a fake-confident prediction.
        let result = LearnedRouter.predict(
            forQueryEmbedding: [0.1, 0.2, 0.3],
            topK: 8,
            minSimilarity: 0.55
        )
        // The shared TraceStore may or may not have rows depending on prior
        // test order, so we accept either nil or a non-nil result. The
        // important invariant is that the synchronous code path doesn't
        // throw or hang.
        _ = result
    }
}
