import XCTest
@testable import Macbot

final class ToolRegistryFilterTests: XCTestCase {

    /// Register a representative subset of real tools so the keyword groups
    /// in ToolRegistry have something to match against.
    private func makeRegistry() async -> ToolRegistry {
        let registry = ToolRegistry()
        let toolNames = [
            // finance
            "get_stock_price", "get_stock_history", "get_market_summary",
            // chart
            "stock_chart", "generate_chart", "comparison_chart",
            // web
            "web_search", "fetch_page",
            // browser
            "browse_url", "browse_and_act", "screenshot_url",
            // files
            "read_file", "write_file", "list_directory", "search_files",
            // macos
            "take_screenshot", "open_app", "open_url", "send_notification",
            "get_clipboard", "set_clipboard", "list_running_apps",
            "get_system_info", "run_command",
            // memory
            "memory_save", "memory_recall", "memory_search", "memory_forget",
            "recall_episodes",
            // skills
            "weather_lookup", "calculator", "unit_convert", "date_calc",
            "define_word", "system_dashboard", "ambient_context",
            // git
            "git_status", "git_log", "git_diff",
            // network
            "ping", "dns_lookup", "port_check", "http_check",
            // calendar
            "calendar_today", "calendar_create", "calendar_week", "reminder_create",
            // imagegen
            "generate_image",
        ]
        for name in toolNames {
            let spec = ToolSpec(name: name, description: name, properties: [:])
            await registry.register(spec) { _ in "" }
        }
        return registry
    }

    private func names(_ specs: [[String: Any]]) -> Set<String> {
        Set(specs.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
    }

    func testFinanceQueryIncludesChartViaCooccurrence() async {
        let registry = await makeRegistry()
        let result = await registry.filteredSpecsAsJSON(for: "what's the stock price of AAPL")
        let n = names(result)
        XCTAssertTrue(n.contains("get_stock_price"))
        // co-occurring chart group should also be pulled in
        XCTAssertTrue(n.contains("stock_chart"), "finance query should pull in chart group")
    }

    func testCodeQueryDoesNotIncludeFinance() async {
        let registry = await makeRegistry()
        let result = await registry.filteredSpecsAsJSON(for: "run python script")
        let n = names(result)
        XCTAssertTrue(n.contains("run_command"))
        XCTAssertFalse(n.contains("get_stock_price"))
    }

    func testWebSearchQueryMatchesWebGroup() async {
        let registry = await makeRegistry()
        let result = await registry.filteredSpecsAsJSON(for: "what is the latest news about AI")
        let n = names(result)
        XCTAssertTrue(n.contains("web_search"))
    }

    func testCalendarQueryMatches() async {
        let registry = await makeRegistry()
        let result = await registry.filteredSpecsAsJSON(for: "what's on my calendar tomorrow")
        let n = names(result)
        XCTAssertTrue(n.contains("calendar_today") || n.contains("calendar_week"))
    }

    func testNoKeywordMatchUsesDefaultFallback() async {
        let registry = await makeRegistry()
        let result = await registry.filteredSpecsAsJSON(for: "asdfqwerty zzz")
        let n = names(result)
        // Default fallback per ToolRegistry source
        XCTAssertTrue(n.contains("web_search"))
        XCTAssertTrue(n.contains("memory_recall"))
        XCTAssertTrue(n.contains("calculator"))
    }

    func testRecentToolsAreUnionedIn() async {
        let registry = await makeRegistry()
        let result = await registry.filteredSpecsAsJSON(
            for: "run python",
            recentTools: ["take_screenshot"]
        )
        let n = names(result)
        XCTAssertTrue(n.contains("take_screenshot"), "recent tools should be unioned")
        XCTAssertTrue(n.contains("run_command"))
    }

    func testGenerateImageQueryMatchesImagegen() async {
        let registry = await makeRegistry()
        let result = await registry.filteredSpecsAsJSON(for: "generate image of a sunset")
        let n = names(result)
        XCTAssertTrue(n.contains("generate_image"))
    }

    func testFilteringIsBoundedNotEntireRegistry() async {
        let registry = await makeRegistry()
        let all = await registry.allSpecs.count
        let result = await registry.filteredSpecsAsJSON(for: "git status")
        // Filtered set should be much smaller than the full registry
        XCTAssertLessThan(result.count, all)
        XCTAssertTrue(names(result).contains("git_status"))
    }
}
