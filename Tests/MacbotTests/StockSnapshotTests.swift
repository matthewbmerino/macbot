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
        if let chartPreviousClose { meta["chartPreviousClose"] = chartPreviousClose }
        if let previousClose { meta["previousClose"] = previousClose }
        if let dayLow { meta["regularMarketDayLow"] = dayLow }
        if let dayHigh { meta["regularMarketDayHigh"] = dayHigh }

        let closesArr: [Any] = closes.map { $0 as Any }
        return [
            "chart": [
                "result": [[
                    "meta": meta,
                    "indicators": [
                        "quote": [[
                            "close": closesArr,
                        ]],
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
}
