import XCTest
@testable import Macbot

/// Locks the contract for the deterministic citation guard.
///
/// This is the systemic anti-fabrication backstop: every numeric token in
/// the model's draft response must appear in the tool-call history for
/// this turn, or the guard fires and forces a regen. The tests below
/// encode the actual user-reported failure cases plus the edge cases that
/// distinguish "fabrication" from "benign English numbers."
final class CitationGuardTests: XCTestCase {

    // MARK: - Numeric extraction

    func testExtractsCurrencyAndPercentAndDecimals() {
        let tokens = CitationGuard.extractNumericTokens(
            from: "Price: $233.65, change +6.20% on $1,234.56 volume, low 223.27"
        )
        let normalized = Set(tokens.map(\.normalized))
        XCTAssertTrue(normalized.contains("233.65"))
        XCTAssertTrue(normalized.contains("6.2"))
        XCTAssertTrue(normalized.contains("1234.56"))
        XCTAssertTrue(normalized.contains("223.27"))
    }

    func testNormalizesCurrencyAndPercentToSameValue() {
        // The guard's whole point: "$233.65", "233.65", "+233.65", and
        // "233.65%" all reference the same numeric magnitude.
        XCTAssertEqual(CitationGuard.normalizeNumeric("$233.65"), "233.65")
        XCTAssertEqual(CitationGuard.normalizeNumeric("233.65"), "233.65")
        XCTAssertEqual(CitationGuard.normalizeNumeric("+233.65"), "233.65")
        XCTAssertEqual(CitationGuard.normalizeNumeric("233.65%"), "233.65")
    }

    func testNormalizesThousandsCommas() {
        XCTAssertEqual(CitationGuard.normalizeNumeric("$1,234,567.89"), "1234567.89")
        XCTAssertEqual(CitationGuard.normalizeNumeric("12,345"), "12345")
    }

    func testTrimsTrailingZerosForComparison() {
        XCTAssertEqual(CitationGuard.normalizeNumeric("100.00"), "100")
        XCTAssertEqual(CitationGuard.normalizeNumeric("6.20"), "6.2")
    }

    // MARK: - Pass-through

    func testPureProseWithoutNumbersIsGrounded() {
        let result = CitationGuard.check(
            draft: "The stock had a strong session today with broad gains.",
            toolHistory: ""
        )
        XCTAssertTrue(result.isGrounded)
        XCTAssertTrue(result.unsourced.isEmpty)
    }

    func testNumbersInToolHistoryArePassedThrough() {
        // The exact AMZN scenario: every number in the draft must appear
        // somewhere in the tool history, possibly with different
        // formatting (currency vs plain, with/without sign).
        let toolHistory = """
        Amazon.com, Inc. (AMZN)
        Price: $233.65
        Day-over-day vs previous close $220.00: up $13.65, +6.20%
        Session range: $223.27 - $233.80 (4.72% spread)
        """
        let draft = "Amazon is at 233.65, up 6.2% from 220 with a session range of 223.27 to 233.80."
        let result = CitationGuard.check(draft: draft, toolHistory: toolHistory)
        XCTAssertTrue(result.isGrounded, "all draft numbers appear in tool history; should pass")
    }

    func testSmallIntegersAreExemptByDefault() {
        // "I called 3 tools" should not require "3" to be in tool history.
        // The exemption protects benign prose like step counts and counts
        // of items.
        let result = CitationGuard.check(
            draft: "I checked 3 sources and found 2 results.",
            toolHistory: ""
        )
        XCTAssertTrue(result.isGrounded)
    }

    // MARK: - The actual fabrication failures

    func testCatchesFabricatedPercentChange() {
        // Tool returned the price and day range but no change percent.
        // Model fabricated "+12.3%" — this is exactly the AMZN/NVDA bug class.
        let toolHistory = """
        AMZN price $233.65, session range $223.27 - $233.80.
        """
        let draft = "Amazon is up 12.3% today at $233.65."
        let result = CitationGuard.check(draft: draft, toolHistory: toolHistory)
        XCTAssertFalse(result.isGrounded)
        XCTAssertTrue(
            result.unsourced.contains { $0.normalized == "12.3" },
            "the fabricated 12.3 must appear in unsourced"
        )
    }

    func testCatchesFabricatedDollarAmount() {
        let toolHistory = "Current AAPL price: $189.42"
        let draft = "AAPL is at $189.42 with a market cap of $2.84T."
        let result = CitationGuard.check(draft: draft, toolHistory: toolHistory)
        XCTAssertFalse(result.isGrounded)
        // 2.84 should be flagged
        XCTAssertTrue(result.unsourced.contains { $0.normalized == "2.84" })
    }

    func testCatchesRoundingDrift() {
        // Tool returned $233.65, model "rounded" to $234. Both round-trip
        // through the normalizer differently — this catches the smoothing
        // failure mode.
        let toolHistory = "Price: $233.65"
        let draft = "Amazon is currently around $234."
        let result = CitationGuard.check(draft: draft, toolHistory: toolHistory)
        XCTAssertFalse(result.isGrounded)
        XCTAssertTrue(result.unsourced.contains { $0.normalized == "234" })
    }

    // MARK: - Regen nudge

    func testRegenerationNudgeContainsTheUnsourcedTokens() {
        let unsourced: [CitationGuard.NumericToken] = [
            .init(original: "+12.3%", normalized: "12.3"),
            .init(original: "$2.84T", normalized: "2.84"),
        ]
        let nudge = CitationGuard.regenerationNudge(for: unsourced)
        XCTAssertTrue(nudge.contains("+12.3%"))
        XCTAssertTrue(nudge.contains("$2.84T"))
        XCTAssertTrue(nudge.contains("do not invent"))
    }

    // MARK: - Allowed literals (escape hatch)

    func testAllowedLiteralsAreTreatedAsGrounded() {
        // Dates from the system prompt should be allowed even if they
        // don't appear in tool history. The caller passes them in via
        // allowedLiterals.
        let result = CitationGuard.check(
            draft: "As of 2026, the rate is 4.5%.",
            toolHistory: "rate: 4.5%",
            allowedLiterals: ["2026"]
        )
        XCTAssertTrue(result.isGrounded)
    }
}
