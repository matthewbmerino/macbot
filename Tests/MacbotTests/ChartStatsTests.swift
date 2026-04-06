import XCTest
@testable import Macbot

/// Locks the contract between the chart Python scripts and the Swift side:
/// every chart that has numeric data must emit a `STATS:{json}` line on
/// stdout, and `formatStatsBlock` must surface those exact numbers as plain
/// text the LLM can quote. This is the fix for the bug where the model
/// hallucinated YTD percentages while the chart drew the correct ones.
final class ChartStatsTests: XCTestCase {

    func testEmptyStdoutProducesEmptyBlock() {
        XCTAssertEqual(ChartTools.formatStatsBlock(stdout: ""), "")
    }

    func testStdoutWithoutStatsLineProducesEmptyBlock() {
        XCTAssertEqual(ChartTools.formatStatsBlock(stdout: "OK\n"), "")
    }

    func testSingleTickerStatsAreRendered() {
        let stdout = #"""
        STATS:{"ticker":"AMZN","period":"ytd","start_price":179.32,"end_price":168.74,"pct_change":-5.9,"period_high":195.20,"period_low":151.61,"data_points":68}
        OK
        """#
        let block = ChartTools.formatStatsBlock(stdout: stdout)
        XCTAssertTrue(block.contains("AMZN YTD: -5.90%"))
        XCTAssertTrue(block.contains("start $179.32"))
        XCTAssertTrue(block.contains("end $168.74"))
        XCTAssertTrue(block.contains("Period high: $195.20"))
        XCTAssertTrue(block.contains("Period low: $151.61"))
        // Instructional preamble must be present so the model uses these
        // numbers verbatim instead of fabricating its own.
        XCTAssertTrue(block.contains("single source of truth"))
    }

    func testComparisonStatsAreRenderedForEveryTicker() {
        let stdout = #"""
        STATS:{"period":"ytd","tickers":[{"ticker":"AMZN","start_price":179.32,"end_price":168.74,"pct_change":-5.9,"data_points":68},{"ticker":"NVDA","start_price":134.29,"end_price":123.27,"pct_change":-8.21,"data_points":68}]}
        OK
        """#
        let block = ChartTools.formatStatsBlock(stdout: stdout)
        XCTAssertTrue(block.contains("AMZN YTD: -5.90%"))
        XCTAssertTrue(block.contains("NVDA YTD: -8.21%"))
        XCTAssertTrue(block.contains("start $179.32"))
        XCTAssertTrue(block.contains("start $134.29"))
        XCTAssertTrue(block.contains("single source of truth"))
    }

    func testPositivePercentGetsExplicitPlusSign() {
        let stdout = #"STATS:{"ticker":"SPY","period":"1y","start_price":500.0,"end_price":550.0,"pct_change":10.0}"#
        let block = ChartTools.formatStatsBlock(stdout: stdout)
        XCTAssertTrue(block.contains("SPY 1Y: +10.00%"))
    }

    func testIntegerValuesAreCoerced() {
        // JSON encoders sometimes drop trailing zeros and emit ints. Make sure
        // we still parse the value rather than silently producing 0.00%.
        let stdout = #"STATS:{"ticker":"X","period":"ytd","start_price":100,"end_price":110,"pct_change":10}"#
        let block = ChartTools.formatStatsBlock(stdout: stdout)
        XCTAssertTrue(block.contains("X YTD: +10.00%"))
        XCTAssertTrue(block.contains("start $100.00"))
        XCTAssertTrue(block.contains("end $110.00"))
    }

    func testMalformedJsonIsIgnoredNotCrashed() {
        let stdout = "STATS:{not valid json}\nOK\n"
        XCTAssertEqual(ChartTools.formatStatsBlock(stdout: stdout), "")
    }
}
