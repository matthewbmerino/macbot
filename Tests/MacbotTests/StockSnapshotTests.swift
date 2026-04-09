import XCTest
@testable import Macbot

/// Locks the contract for the Yahoo v8 chart parser. The bug this prevents:
/// asking "how did Amazon do today?" returned a confident "+0.00%" because
/// the parser was reading `chartPreviousClose` from the meta block, and
/// that field is unreliable for intraday queries — it sometimes returns
/// the current regular market price (or today's open) instead of
/// yesterday's actual close.
///
/// The fix reads the previous-day close from the closes array directly
/// (second-to-last bar in a multi-day query) and only falls back to meta
/// fields if the array is too short.
final class StockSnapshotTests: XCTestCase {

    /// Build a Yahoo-style chart response with the given closes array and
    /// optional meta overrides. The closes array's LAST entry represents
    /// today (or the most recent bar), and the SECOND-TO-LAST is yesterday.
    private func makeJSON(
        symbol: String = "AMZN",
        name: String = "Amazon.com, Inc.",
        price: Double,
        closes: [Double],
        opens: [Double]? = nil,
        regularMarketOpen: Double? = nil,
        dayLow: Double? = nil,
        dayHigh: Double? = nil,
        chartPreviousClose: Double? = nil,
        previousClose: Double? = nil
    ) -> [String: Any] {
        var meta: [String: Any] = [
            "symbol": symbol,
            "shortName": name,
            "regularMarketPrice": price,
        ]
        if let regularMarketOpen { meta["regularMarketOpen"] = regularMarketOpen }
        if let chartPreviousClose { meta["chartPreviousClose"] = chartPreviousClose }
        if let previousClose { meta["previousClose"] = previousClose }
        if let dayLow { meta["regularMarketDayLow"] = dayLow }
        if let dayHigh { meta["regularMarketDayHigh"] = dayHigh }

        var quote: [String: Any] = [
            "close": closes.map { $0 as Any },
        ]
        if let opens { quote["open"] = opens.map { $0 as Any } }
        return [
            "chart": [
                "result": [[
                    "meta": meta,
                    "indicators": [
                        "quote": [quote],
                    ],
                ]],
            ],
        ]
    }

    // MARK: - The bug

    func testReadsPreviousCloseFromClosesArrayNotMeta() throws {
        // The exact failure mode from the bug report: Yahoo's meta has
        // chartPreviousClose == regularMarketPrice (the buggy intraday
        // behavior). The parser must NOT use that field; it must use the
        // second-to-last bar from the closes array, which has yesterday's
        // real close ($220.00).
        let json = makeJSON(
            price: 233.65,
            closes: [220.00, 233.65],         // [yesterday, today]
            chartPreviousClose: 233.65        // bad meta field
        )
        let snap = try XCTUnwrap(FinanceTools.parseStockSnapshot(json: json, symbol: "AMZN"))
        XCTAssertEqual(snap.prevClose, 220.00, accuracy: 0.001)
        XCTAssertEqual(snap.change, 13.65, accuracy: 0.001)
        XCTAssertEqual(snap.changePct, 6.20, accuracy: 0.05)
    }

    func testFallsBackToMetaPreviousCloseIfClosesArrayTooShort() throws {
        // Edge case: only one bar in the closes array (e.g., first hour of
        // a fresh trading day with limited intraday data). Fall back to
        // meta.previousClose, NOT meta.chartPreviousClose.
        let json = makeJSON(
            price: 100.00,
            closes: [100.00],            // only today
            chartPreviousClose: 100.00,  // bad
            previousClose: 95.00         // good
        )
        let snap = try XCTUnwrap(FinanceTools.parseStockSnapshot(json: json, symbol: "TEST"))
        XCTAssertEqual(snap.prevClose, 95.00, accuracy: 0.001)
    }

    func testFallsBackToChartPreviousCloseIfPreviousCloseAbsent() throws {
        // If even meta.previousClose is missing, chartPreviousClose is the
        // last resort. Better to have a possibly-wrong number than nothing.
        let json = makeJSON(
            price: 100.00,
            closes: [100.00],
            chartPreviousClose: 90.00
        )
        let snap = try XCTUnwrap(FinanceTools.parseStockSnapshot(json: json, symbol: "TEST"))
        XCTAssertEqual(snap.prevClose, 90.00, accuracy: 0.001)
    }

    func testZeroesPrevCloseWhenItExactlyMatchesPrice() throws {
        // Final sanity guard: if the parser ends up with prevClose == price
        // (essentially impossible in real markets — yesterday's close
        // exactly matching today's current price to the cent), the data is
        // suspect. Return prevClose = 0 so downstream formatters can show
        // "unavailable" rather than a confident "+0.00%".
        let json = makeJSON(
            price: 233.65,
            closes: [233.65, 233.65],   // both bars are identical
            chartPreviousClose: 233.65,
            previousClose: 233.65
        )
        let snap = try XCTUnwrap(FinanceTools.parseStockSnapshot(json: json, symbol: "AMZN"))
        XCTAssertEqual(snap.prevClose, 0)
        XCTAssertEqual(snap.changePct, 0)  // 0 because prevClose=0
    }

    // MARK: - Happy path

    func testHappyPathParsesAllFields() throws {
        let json = makeJSON(
            symbol: "AMZN",
            name: "Amazon.com, Inc.",
            price: 233.65,
            closes: [221.10, 222.40, 220.00, 233.65],
            dayLow: 223.27,
            dayHigh: 233.80
        )
        let snap = try XCTUnwrap(FinanceTools.parseStockSnapshot(json: json, symbol: "AMZN"))
        XCTAssertEqual(snap.symbol, "AMZN")
        XCTAssertEqual(snap.name, "Amazon.com, Inc.")
        XCTAssertEqual(snap.price, 233.65, accuracy: 0.001)
        XCTAssertEqual(snap.prevClose, 220.00, accuracy: 0.001)
        XCTAssertEqual(snap.dayLow, 223.27, accuracy: 0.001)
        XCTAssertEqual(snap.dayHigh, 233.80, accuracy: 0.001)
        XCTAssertGreaterThan(snap.changePct, 6.0)
    }

    func testNegativeChange() throws {
        let json = makeJSON(
            price: 100.00,
            closes: [110.00, 100.00]
        )
        let snap = try XCTUnwrap(FinanceTools.parseStockSnapshot(json: json, symbol: "TEST"))
        XCTAssertEqual(snap.change, -10.00, accuracy: 0.001)
        XCTAssertEqual(snap.changePct, -9.09, accuracy: 0.05)
    }

    func testReturnsNilForMalformedJSON() {
        XCTAssertNil(FinanceTools.parseStockSnapshot(json: [:], symbol: "X"))
        XCTAssertNil(FinanceTools.parseStockSnapshot(json: ["chart": ["result": []]], symbol: "X"))
    }

    func testReturnsNilForZeroPrice() {
        let json = makeJSON(price: 0, closes: [100, 0])
        XCTAssertNil(FinanceTools.parseStockSnapshot(json: json, symbol: "X"))
    }

    // MARK: - Intraday + day range (the "essentially flat" bug)

    func testIntradayChangeFromMetaOpen() throws {
        // The model previously called a $10 day range "essentially flat".
        // The fix gives the formatter an explicit intraday change number
        // computed from today's open. Verify the snapshot exposes it.
        let json = makeJSON(
            price: 233.65,
            closes: [233.65, 233.65],   // prevClose unreliable
            regularMarketOpen: 228.40,
            dayLow: 223.27,
            dayHigh: 233.80
        )
        let snap = try XCTUnwrap(FinanceTools.parseStockSnapshot(json: json, symbol: "AMZN"))
        XCTAssertEqual(snap.dayOpen, 228.40, accuracy: 0.001)
        XCTAssertEqual(snap.intradayChange, 5.25, accuracy: 0.001)
        XCTAssertEqual(snap.intradayChangePct, 2.298, accuracy: 0.01)
    }

    func testIntradayFallsBackToOpensArrayWhenMetaMissing() throws {
        // Some Yahoo responses don't carry regularMarketOpen in meta but
        // do carry the indicators.quote.open array. Use the last entry.
        let json = makeJSON(
            price: 100.00,
            closes: [95.0, 100.0],
            opens: [94.0, 96.0]
        )
        let snap = try XCTUnwrap(FinanceTools.parseStockSnapshot(json: json, symbol: "TEST"))
        XCTAssertEqual(snap.dayOpen, 96.0, accuracy: 0.001)
        XCTAssertEqual(snap.intradayChangePct, 4.166, accuracy: 0.01)
    }

    func testDayRangePercentMatchesArithmetic() throws {
        let json = makeJSON(
            price: 233.65,
            closes: [220.0, 233.65],
            dayLow: 223.27,
            dayHigh: 233.80
        )
        let snap = try XCTUnwrap(FinanceTools.parseStockSnapshot(json: json, symbol: "AMZN"))
        XCTAssertEqual(snap.dayRange, 10.53, accuracy: 0.001)
        // 10.53 / 223.27 * 100 ≈ 4.7163
        XCTAssertEqual(snap.dayRangePct, 4.7163, accuracy: 0.01)
    }

    // MARK: - Formatter (the surface the model actually sees)

    func testFormatIncludesIntradayAndDayRangeWithExplicitLabels() {
        let snap = FinanceTools.StockSnapshot(
            symbol: "AMZN",
            name: "Amazon.com, Inc.",
            price: 233.65,
            prevClose: 220.00,
            dayOpen: 228.40,
            dayHigh: 233.80,
            dayLow: 223.27
        )
        let body = FinanceTools.formatStockSnapshot(snap)
        // Headline day-over-day vs prev close
        XCTAssertTrue(body.contains("Day-over-day"))
        XCTAssertTrue(body.contains("$220.00"))
        XCTAssertTrue(body.contains("+6.20%"))
        // Intraday vs today's open
        XCTAssertTrue(body.contains("Intraday"))
        XCTAssertTrue(body.contains("$228.40"))
        XCTAssertTrue(body.contains("+2.30%"))
        // Session range with absolute spread + percent
        XCTAssertTrue(body.contains("Session range"))
        XCTAssertTrue(body.contains("$223.27"))
        XCTAssertTrue(body.contains("$233.80"))
        XCTAssertTrue(body.contains("4.72%"))
    }

    func testFormatNeverCallsActiveSessionFlat() {
        // The exact failure: prevClose unavailable, but the day moved
        // ~4.7% intraday. The formatter must include an explicit
        // anti-flat note so the small model can't summarize as "flat".
        let snap = FinanceTools.StockSnapshot(
            symbol: "AMZN",
            name: "Amazon.com, Inc.",
            price: 233.65,
            prevClose: 0,                // unavailable
            dayOpen: 228.40,
            dayHigh: 233.80,
            dayLow: 223.27
        )
        let body = FinanceTools.formatStockSnapshot(snap)
        XCTAssertTrue(body.contains("unavailable"),
                      "previous-close fallback line must surface the unknown state")
        // Intraday is still concrete and meaningful
        XCTAssertTrue(body.contains("Intraday"))
        XCTAssertTrue(body.contains("+2.30%"))
        // Session range carries a real percent
        XCTAssertTrue(body.contains("4.72%"))
        // Anti-fabrication note must fire because the session has clear movement
        XCTAssertTrue(body.contains("NOT flat"),
                      "active session must carry the explicit not-flat instruction")
    }

    func testFormatGenuinelyFlatSessionDoesNotEmitNotFlatNote() {
        // The opposite check: a session with truly tiny movement (well
        // under the 0.5% thresholds for both intraday and range) should
        // NOT carry the not-flat note — it would be wrong to claim
        // movement that didn't happen.
        let snap = FinanceTools.StockSnapshot(
            symbol: "TEST",
            name: "Test Inc",
            price: 100.00,
            prevClose: 100.00,
            dayOpen: 99.99,
            dayHigh: 100.05,
            dayLow: 99.95
        )
        let body = FinanceTools.formatStockSnapshot(snap)
        XCTAssertFalse(body.contains("NOT flat"),
                       "genuinely flat session should not emit the anti-flat note")
    }
}
