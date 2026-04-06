import XCTest
@testable import Macbot

/// Locks the contract for the GroundedResponse helper. The shape of the
/// header is what makes the small model quote tool data verbatim — if it
/// drifts, the steering effect erodes silently.
final class GroundedResponseTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1_777_000_000)  // 2026-04-24T03:06:40Z

    func testFormatProducesSourceAndUseTheseExactValuesPreamble() {
        let result = GroundedResponse.format(
            source: "Yahoo Finance",
            body: "AAPL $189.42",
            now: fixedDate
        )
        XCTAssertTrue(result.contains("Data from Yahoo Finance"))
        XCTAssertTrue(result.contains("use these exact values in your response"))
        XCTAssertTrue(result.contains("AAPL $189.42"))
    }

    func testFormatIncludesISOTimestampByDefault() {
        let result = GroundedResponse.format(
            source: "Yahoo Finance",
            body: "x",
            now: fixedDate
        )
        XCTAssertTrue(result.contains("2026-04-24T03:06:40Z"),
                      "default policy should append a UTC timestamp")
    }

    func testFormatOmitsTimestampWhenPolicyIsNone() {
        let result = GroundedResponse.format(
            source: "math",
            timePolicy: .none,
            body: "1 + 1 = 2",
            now: fixedDate
        )
        XCTAssertFalse(result.contains("2026"))
        XCTAssertFalse(result.contains(" at "))
    }

    func testSearchResultsEchoesQueryAndForbidsFabricatedURLs() {
        let result = GroundedResponse.searchResults(
            source: "DuckDuckGo",
            query: "swift package manager",
            body: "[Title]\nSnippet\nhttps://example.com",
            now: fixedDate
        )
        XCTAssertTrue(result.contains("Search results from DuckDuckGo"))
        XCTAssertTrue(result.contains("\"swift package manager\""))
        XCTAssertTrue(result.contains("do not invent URLs"))
        XCTAssertTrue(result.contains("https://example.com"))
        XCTAssertTrue(result.contains("2026-04-24T03:06:40Z"))
    }

    func testISOTimestampFormatIsStable() {
        // ISO-8601 with no fractional seconds, UTC zulu suffix.
        XCTAssertEqual(GroundedResponse.isoTimestamp(fixedDate), "2026-04-24T03:06:40Z")
    }
}
