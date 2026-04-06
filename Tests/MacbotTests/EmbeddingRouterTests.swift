import XCTest
@testable import Macbot

final class EmbeddingRouterTests: XCTestCase {

    func testClassifyVisionShortcutsOnImageAttachments() async {
        let mock = MockInferenceProvider()
        let router = EmbeddingRouter(client: mock)
        // No calibration needed — image presence bypasses embedding entirely.
        let category = await router.classify(message: "anything", hasImages: true)
        XCTAssertEqual(category, .vision)
        XCTAssertTrue(mock.embedCalls.isEmpty, "should not call embed when images present")
    }

    func testFallsBackToGeneralWhenNotCalibrated() async {
        let mock = MockInferenceProvider()
        let router = EmbeddingRouter(client: mock)
        let category = await router.classify(message: "write a python function")
        XCTAssertEqual(category, .general)
        XCTAssertTrue(mock.embedCalls.isEmpty, "no embedding call before calibration")
    }

    func testCalibrationCallsEmbedForEachCategory() async {
        let mock = MockInferenceProvider()
        let router = EmbeddingRouter(client: mock)
        await router.calibrate()
        // 5 categories × 1 call each (batched per category)
        XCTAssertEqual(mock.embedCalls.count, AgentCategory.allCases.count)
    }

    func testClassifiesCoderQuery() async {
        let mock = MockInferenceProvider()
        let router = EmbeddingRouter(client: mock)
        await router.calibrate()
        let category = await router.classify(message: "write a python function to fix this bug")
        XCTAssertEqual(category, .coder)
    }

    func testClassifiesReasonerQuery() async {
        let mock = MockInferenceProvider()
        let router = EmbeddingRouter(client: mock)
        await router.calibrate()
        let category = await router.classify(message: "calculate the derivative and prove the irrational result")
        XCTAssertEqual(category, .reasoner)
    }

    func testClassifiesRagQuery() async {
        let mock = MockInferenceProvider()
        let router = EmbeddingRouter(client: mock)
        await router.calibrate()
        let category = await router.classify(message: "what does the documentation say about the database schema")
        XCTAssertEqual(category, .rag)
    }

    func testClassifyFallsBackToGeneralOnEmbedError() async {
        let mock = MockInferenceProvider()
        let router = EmbeddingRouter(client: mock)
        await router.calibrate()
        mock.embedError = NSError(domain: "test", code: 1)
        let category = await router.classify(message: "write a python function")
        XCTAssertEqual(category, .general)
    }

    func testLowConfidenceFallsBackToGeneral() async {
        let mock = MockInferenceProvider()
        let router = EmbeddingRouter(client: mock)
        await router.calibrate()
        // Negative-general query: dot product with the general centroid (dim 0
        // dominant) is strongly negative, with other category centroids it's
        // ~0. Max is some non-general category but sim is below the 0.3
        // confidence threshold → router falls back to general.
        mock.embedOverride = [[-1, 0, 0, 0, 0, 0, 0, 0]]
        let category = await router.classify(message: "xyz")
        XCTAssertEqual(category, .general)
    }

    func testClassifyWithScoresReturnsAllCategories() async {
        let mock = MockInferenceProvider()
        let router = EmbeddingRouter(client: mock)
        await router.calibrate()
        let scores = await router.classifyWithScores(message: "write a python function")
        XCTAssertEqual(scores.count, AgentCategory.allCases.count)
        // Sorted descending
        for i in 1..<scores.count {
            XCTAssertGreaterThanOrEqual(scores[i - 1].1, scores[i].1)
        }
    }
}
