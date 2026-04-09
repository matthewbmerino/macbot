import Foundation

enum FinanceTools {
    static let stockPriceSpec = ToolSpec(
        name: "get_stock_price",
        description: "Get the current stock price and key financial data for a ticker symbol. Use this for any question about stock prices, market data, or company financials.",
        properties: ["ticker": .init(type: "string", description: "Stock ticker symbol (e.g., AMZN, AAPL, GOOGL, TSLA)")],
        required: ["ticker"]
    )

    static let stockHistorySpec = ToolSpec(
        name: "get_stock_history",
        description: "Get historical stock price data for a ticker. Use for price trends, performance over time, and YTD returns.",
        properties: [
            "ticker": .init(type: "string", description: "Stock ticker symbol"),
            "period": .init(type: "string", description: "Time period: 1d, 5d, 1mo, 3mo, 6mo, ytd, 1y, 5y. Use 'ytd' for year-to-date returns."),
        ],
        required: ["ticker"]
    )

    static let marketSummarySpec = ToolSpec(
        name: "get_market_summary",
        description: "Get a summary of major market indices (S&P 500, Nasdaq, Dow). Use for general market questions.",
        properties: [:]
    )

    static func register(on registry: ToolRegistry) async {
        await registry.register(stockPriceSpec) { args in
            await getStockPrice(ticker: args["ticker"] as? String ?? "")
        }
        await registry.register(stockHistorySpec) { args in
            await getStockHistory(
                ticker: args["ticker"] as? String ?? "",
                period: args["period"] as? String ?? "1mo"
            )
        }
        await registry.register(marketSummarySpec) { _ in
            await getMarketSummary()
        }
    }

    // MARK: - Yahoo Finance via URL (no yfinance in Swift, use the JSON API)

    /// A parsed snapshot of a stock's current state. Pure data — no
    /// formatting, no IO — so the parsing logic is unit-testable against
    /// stubbed Yahoo JSON.
    struct StockSnapshot {
        let symbol: String
        let name: String
        let price: Double
        let prevClose: Double
        let dayHigh: Double
        let dayLow: Double

        var change: Double { price - prevClose }
        var changePct: Double { prevClose > 0 ? (change / prevClose * 100) : 0 }
    }

    /// Parse a Yahoo v8 chart response (with `interval=1d&range=5d` so the
    /// closes array contains yesterday's bar) into a snapshot.
    ///
    /// The previous-day close is read from `validCloses[count - 2]` — the
    /// second-to-last bar — instead of from `meta.chartPreviousClose`.
    /// `chartPreviousClose` is unreliable on intraday queries: it sometimes
    /// returns today's regular market open, which produces a +0.00% change
    /// when the user is asking what the stock did "today". Reading directly
    /// from the closes array is the only fix that's actually correct
    /// against today's session.
    static func parseStockSnapshot(json: [String: Any], symbol: String) -> StockSnapshot? {
        guard let chart = json["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first,
              let meta = result["meta"] as? [String: Any]
        else {
            return nil
        }

        let price = meta["regularMarketPrice"] as? Double ?? 0
        guard price > 0 else { return nil }

        let name = meta["shortName"] as? String ?? meta["symbol"] as? String ?? symbol
        let dayHigh = meta["regularMarketDayHigh"] as? Double ?? 0
        let dayLow = meta["regularMarketDayLow"] as? Double ?? 0

        // Authoritative previous close: read the closes array from the chart
        // indicators. The last entry is today (or the most recent bar) and
        // the second-to-last is the previous trading day. This is the only
        // reliable way to get yesterday's close from the v8 chart endpoint.
        var prevClose: Double = 0
        if let indicators = result["indicators"] as? [String: Any],
           let quotes = (indicators["quote"] as? [[String: Any]])?.first,
           let closes = quotes["close"] as? [Double?] {
            let validCloses = closes.compactMap { $0 }
            if validCloses.count >= 2 {
                prevClose = validCloses[validCloses.count - 2]
            }
        }

        // Fall back to meta fields only if the closes array was too short.
        // Prefer `previousClose` over `chartPreviousClose` because the
        // latter is the field that has the intraday-bug behavior.
        if prevClose <= 0 {
            prevClose = meta["previousClose"] as? Double
                     ?? meta["chartPreviousClose"] as? Double
                     ?? 0
        }

        // Final sanity check: if prevClose ended up exactly equal to price,
        // we're almost certainly looking at bad data (the chance of yesterday
        // closing at exactly today's current price to the cent is essentially
        // zero). Return prevClose = 0 so the formatter shows uncertainty
        // rather than a confident "+0.00%".
        if abs(prevClose - price) < 0.0001 {
            prevClose = 0
        }

        return StockSnapshot(
            symbol: symbol,
            name: name,
            price: price,
            prevClose: prevClose,
            dayHigh: dayHigh,
            dayLow: dayLow
        )
    }

    private static func getStockPrice(ticker: String) async -> String {
        let symbol = ticker.uppercased().trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return "Error: empty ticker" }

        // range=5d so the closes array contains yesterday's bar — needed
        // because chartPreviousClose is unreliable on intraday queries.
        // 5d covers weekends and at least one prior trading day reliably.
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=5d") else {
            return "Error: invalid ticker"
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return "Error fetching \(symbol): HTTP \(http.statusCode)"
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "Error: malformed Yahoo response for \(symbol)"
            }
            guard let snapshot = parseStockSnapshot(json: json, symbol: symbol) else {
                return "Could not find data for: \(symbol)"
            }

            let direction = snapshot.change >= 0 ? "up" : "down"

            var body = "\(snapshot.name) (\(snapshot.symbol))\n"
            if snapshot.prevClose > 0 {
                body += "Price: $\(String(format: "%.2f", snapshot.price)) (\(direction) $\(String(format: "%.2f", abs(snapshot.change))), \(String(format: "%+.2f", snapshot.changePct))%)\n"
                body += "Previous close: $\(String(format: "%.2f", snapshot.prevClose))"
            } else {
                // Defensive path: previous close was unreliable. Tell the
                // model the price but explicitly say change is unknown so
                // it doesn't fabricate a number to fill the gap.
                body += "Price: $\(String(format: "%.2f", snapshot.price))\n"
                body += "Previous close: unavailable — change percent unknown for this session"
            }

            if snapshot.dayLow > 0 && snapshot.dayHigh > 0 {
                body += "\nDay range: $\(String(format: "%.2f", snapshot.dayLow)) - $\(String(format: "%.2f", snapshot.dayHigh))"
            }

            return GroundedResponse.format(source: "Yahoo Finance", body: body)

        } catch {
            return "Error fetching stock data: \(error.localizedDescription)"
        }
    }

    private static func getStockHistory(ticker: String, period: String) async -> String {
        let symbol = ticker.uppercased().trimmingCharacters(in: .whitespaces)

        // Normalize period: handle "year to date", "year-to-date", etc.
        let normalizedPeriod: String
        let lowerPeriod = period.lowercased().trimmingCharacters(in: .whitespaces)
        if lowerPeriod == "ytd" || lowerPeriod.contains("year to date") || lowerPeriod.contains("year-to-date") {
            normalizedPeriod = "ytd"
        } else {
            normalizedPeriod = period
        }

        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=\(normalizedPeriod)") else {
            return "Error: invalid ticker"
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10

            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let chart = json?["chart"] as? [String: Any],
                  let results = chart["result"] as? [[String: Any]],
                  let result = results.first,
                  let meta = result["meta"] as? [String: Any],
                  let indicators = result["indicators"] as? [String: Any],
                  let quotes = (indicators["quote"] as? [[String: Any]])?.first,
                  let closes = quotes["close"] as? [Double?],
                  let highs = quotes["high"] as? [Double?],
                  let lows = quotes["low"] as? [Double?]
            else {
                return "No data for \(symbol) over \(normalizedPeriod)"
            }

            let validCloses = closes.compactMap { $0 }
            guard !validCloses.isEmpty else {
                return "No data for \(symbol)"
            }

            let currentPrice = meta["regularMarketPrice"] as? Double ?? validCloses.last ?? 0

            // For YTD: use chartPreviousClose (Dec 31 close) as the starting price
            // For other periods: use the first close in the range
            let startPrice: Double
            if normalizedPeriod == "ytd" {
                startPrice = meta["chartPreviousClose"] as? Double ?? validCloses.first ?? 0
            } else {
                startPrice = validCloses.first ?? 0
            }

            let high = highs.compactMap { $0 }.max() ?? 0
            let low = lows.compactMap { $0 }.min() ?? 0
            let change = currentPrice - startPrice
            let changePct = startPrice > 0 ? (change / startPrice * 100) : 0

            let periodLabel = normalizedPeriod == "ytd" ? "year-to-date" : normalizedPeriod

            let body = """
            \(symbol) — \(periodLabel) performance
            Start: $\(String(format: "%.2f", startPrice))
            Current: $\(String(format: "%.2f", currentPrice))
            Change: $\(String(format: "%+.2f", change)) (\(String(format: "%+.2f", changePct))%)
            Period high: $\(String(format: "%.2f", high))
            Period low: $\(String(format: "%.2f", low))
            Trading days: \(validCloses.count)
            """
            return GroundedResponse.format(source: "Yahoo Finance", body: body)

        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private static func getMarketSummary() async -> String {
        let indices = [
            ("S&P 500", "^GSPC"),
            ("Nasdaq", "^IXIC"),
            ("Dow Jones", "^DJI"),
        ]

        var lines: [String] = []
        for (name, symbol) in indices {
            let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
            guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=1d") else {
                lines.append("  \(name): unavailable")
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 10

                let (data, _) = try await URLSession.shared.data(for: request)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                if let chart = json?["chart"] as? [String: Any],
                   let results = chart["result"] as? [[String: Any]],
                   let meta = results.first?["meta"] as? [String: Any] {
                    let price = meta["regularMarketPrice"] as? Double ?? 0
                    let prev = meta["chartPreviousClose"] as? Double ?? 0
                    let change = price - prev
                    let pct = prev > 0 ? (change / prev * 100) : 0
                    let sign = change >= 0 ? "+" : ""
                    lines.append("  \(name): \(String(format: "%,.2f", price)) (\(sign)\(String(format: "%.2f", change)), \(sign)\(String(format: "%.2f", pct))%)")
                } else {
                    lines.append("  \(name): unavailable")
                }
            } catch {
                lines.append("  \(name): unavailable")
            }
        }

        return GroundedResponse.format(
            source: "Yahoo Finance",
            body: lines.joined(separator: "\n")
        )
    }
}
