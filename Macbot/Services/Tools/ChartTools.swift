import Foundation

enum ChartTools {
    // MARK: - Tool Specs

    static let stockChartSpec = ToolSpec(
        name: "stock_chart",
        description: "Generate a professional stock price chart for any ticker. Returns an inline image. Use this whenever the user asks to see, show, display, or chart stock/crypto price data.",
        properties: [
            "ticker": .init(type: "string", description: "Stock or crypto ticker symbol (e.g., AAPL, MSFT, BTC-USD, ETH-USD)"),
            "period": .init(type: "string", description: "Time period: 1d, 5d, 1mo, 3mo, 6mo, ytd, 1y, 5y (default: ytd)"),
            "compare": .init(type: "string", description: "Optional second ticker to compare (e.g., MSFT to compare vs AAPL)"),
        ],
        required: ["ticker"]
    )

    static let generateChartSpec = ToolSpec(
        name: "generate_chart",
        description: "Generate a custom chart from Python matplotlib code. Use stock_chart instead for stock/crypto charts — it's faster and more reliable. Only use this for custom/non-stock visualizations.",
        properties: [
            "code": .init(type: "string", description: "Python matplotlib code. OUTPUT_PATH is predefined. Call plt.savefig(OUTPUT_PATH) at the end."),
            "title": .init(type: "string", description: "Brief description of the chart"),
        ],
        required: ["code"]
    )

    static let grabFileSpec = ToolSpec(
        name: "grab_file",
        description: "Grab a file and include it in the response. Images display inline. Text files show content.",
        properties: ["path": .init(type: "string", description: "Path to the file")],
        required: ["path"]
    )

    static func register(on registry: ToolRegistry) async {
        await registry.register(stockChartSpec) { args in
            await generateStockChart(
                ticker: args["ticker"] as? String ?? "",
                period: args["period"] as? String ?? "ytd",
                compare: args["compare"] as? String
            )
        }
        await registry.register(generateChartSpec) { args in
            await generateCustomChart(code: args["code"] as? String ?? "", title: args["title"] as? String ?? "Chart")
        }
        await registry.register(grabFileSpec) { args in
            grabFile(path: args["path"] as? String ?? "")
        }
    }

    // MARK: - Stock Chart (zero model effort — hardcoded reliable script)

    static func generateStockChart(ticker: String, period: String, compare: String?) async -> String {
        let symbol = ticker.uppercased().trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty else { return "Error: empty ticker" }

        let chartId = UUID().uuidString.prefix(8)
        let chartPath = "/tmp/macbot_stock_\(chartId).png"

        // Normalize period
        let normalizedPeriod: String
        let lower = period.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.contains("year to date") || lower.contains("year-to-date") {
            normalizedPeriod = "ytd"
        } else if lower.isEmpty {
            normalizedPeriod = "ytd"
        } else {
            normalizedPeriod = lower
        }

        // Build Python script — no model involvement, just data + chart
        var script = """
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        import matplotlib.dates as mdates
        import json, urllib.request, sys
        from datetime import datetime

        plt.style.use('dark_background')
        plt.rcParams.update({
            'figure.facecolor': '#0a0a0a',
            'axes.facecolor': '#0a0a0a',
            'axes.edgecolor': '#333333',
            'axes.labelcolor': '#e8e8e8',
            'text.color': '#e8e8e8',
            'xtick.color': '#999999',
            'ytick.color': '#999999',
            'grid.color': '#1e1e1e',
            'grid.alpha': 0.3,
            'font.size': 11,
            'axes.grid': True,
        })

        ticker = '\(symbol)'
        period = '\(normalizedPeriod)'

        def fetch_yahoo(sym, per):
            url = f'https://query1.finance.yahoo.com/v8/finance/chart/{sym}?interval=1d&range={per}'
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read())
            result = data['chart']['result'][0]
            timestamps = result['timestamp']
            closes = result['indicators']['quote'][0]['close']
            dates = [datetime.fromtimestamp(t) for t in timestamps]
            prices = [c for c in closes if c is not None]
            dates = dates[:len(prices)]
            return dates, prices

        # Try yfinance first, fall back to direct Yahoo API
        dates, prices = None, None
        try:
            import yfinance as yf
            data = yf.download(ticker, period=period, progress=False, timeout=10)
            if not data.empty:
                close = data['Close']
                if hasattr(close, 'columns'):
                    close = close.iloc[:, 0]
                dates = list(data.index)
                prices = list(close)
        except:
            pass

        if not dates or not prices:
            try:
                dates, prices = fetch_yahoo(ticker, period)
            except Exception as e:
                print(f'ERROR: {e}', file=sys.stderr)
                sys.exit(1)

        if not prices:
            print(f'ERROR: No data for {ticker}', file=sys.stderr)
            sys.exit(1)

        fig, ax = plt.subplots(figsize=(12, 6))
        ax.plot(dates, prices, color='#6366f1', linewidth=1.5, label=ticker)
        ax.fill_between(dates, prices, alpha=0.08, color='#6366f1')

        """

        // Add comparison ticker if provided
        if let comp = compare?.uppercased().trimmingCharacters(in: .whitespaces), !comp.isEmpty {
            script += """

        # Comparison ticker
        comp_dates, comp_prices = None, None
        try:
            import yfinance as yf
            cd = yf.download('\(comp)', period=period, progress=False, timeout=10)
            if not cd.empty:
                cc = cd['Close']
                if hasattr(cc, 'columns'):
                    cc = cc.iloc[:, 0]
                comp_dates, comp_prices = list(cd.index), list(cc)
        except:
            pass
        if not comp_dates:
            try:
                comp_dates, comp_prices = fetch_yahoo('\(comp)', period)
            except:
                pass

        if comp_prices:
            ax.clear()
            pct1 = [(p / prices[0] - 1) * 100 for p in prices]
            pct2 = [(p / comp_prices[0] - 1) * 100 for p in comp_prices]
            ax.plot(dates, pct1, color='#6366f1', linewidth=1.5, label=ticker)
            ax.plot(comp_dates, pct2, color='#22c55e', linewidth=1.5, label='\(comp)')
            ax.axhline(y=0, color='#444444', linewidth=0.5, linestyle='--')
            ax.set_ylabel('% Change')
            ax.legend(loc='upper left', framealpha=0.3)

        """
        }

        script += """

        # Price annotations
        start_price = prices[0]
        end_price = prices[-1]
        change = end_price - start_price
        pct_change = (change / start_price) * 100
        color = '#22c55e' if change >= 0 else '#ef4444'
        arrow = '+' if change >= 0 else ''

        period_label = period.upper() if period != 'ytd' else 'YTD'
        title = f'{ticker} {period_label}  |  ${end_price:.2f}  ({arrow}{pct_change:.1f}%)'
        ax.set_title(title, fontsize=14, fontweight='bold', color=color, pad=15)

        # Format x-axis dates
        if len(prices) > 200:
            ax.xaxis.set_major_locator(mdates.MonthLocator(interval=2))
        elif len(prices) > 60:
            ax.xaxis.set_major_locator(mdates.MonthLocator())
        else:
            ax.xaxis.set_major_locator(mdates.WeekdayLocator(interval=1))
        ax.xaxis.set_major_formatter(mdates.DateFormatter('%b %d'))
        fig.autofmt_xdate(rotation=30)

        # Clean up
        ax.spines['top'].set_visible(False)
        ax.spines['right'].set_visible(False)
        ax.tick_params(axis='both', which='both', length=0)

        plt.tight_layout()
        plt.savefig('\(chartPath)', dpi=150, bbox_inches='tight')
        plt.close('all')
        print('OK')
        """

        return await runPython(script: script, chartPath: chartPath, label: "\(symbol) \(normalizedPeriod.uppercased()) chart")
    }

    // MARK: - Custom Chart (model-written code)

    static func generateCustomChart(code: String, title: String) async -> String {
        let chartId = UUID().uuidString.prefix(8)
        let chartPath = "/tmp/macbot_chart_\(chartId).png"

        let setup = """
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        plt.style.use('dark_background')
        plt.rcParams.update({
            'figure.facecolor': '#0a0a0a', 'axes.facecolor': '#0a0a0a',
            'axes.edgecolor': '#333333', 'axes.labelcolor': '#e8e8e8',
            'text.color': '#e8e8e8', 'xtick.color': '#999999', 'ytick.color': '#999999',
            'grid.color': '#1e1e1e', 'grid.alpha': 0.3, 'figure.figsize': (12, 6),
            'font.size': 11, 'axes.grid': True,
        })
        OUTPUT_PATH = '\(chartPath)'
        """

        var userCode = code
        if !userCode.contains("savefig") {
            userCode += "\nplt.tight_layout()\nplt.savefig(OUTPUT_PATH, dpi=150, bbox_inches='tight')"
        }

        let fullCode = "\(setup)\n\(userCode)\nplt.close('all')\nprint('OK')"
        return await runPython(script: fullCode, chartPath: chartPath, label: title)
    }

    // MARK: - Python Runner

    private static func runPython(script: String, chartPath: String, label: String) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", script]
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()

            let deadline = Date().addingTimeInterval(30)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            if process.isRunning {
                process.terminate()
                return "Error: chart generation timed out after 30s"
            }

            if FileManager.default.fileExists(atPath: chartPath) {
                return "\(label)\n[IMAGE:\(chartPath)]"
            }

            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if stderr.contains("No module named") {
                let module = stderr.components(separatedBy: "No module named").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "'", with: "") ?? "unknown"
                return "Chart failed — missing Python module: \(module). Run: pip3 install \(module)"
            }
            return "Chart failed: \(String(stderr.prefix(300)))"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - File Grab

    static func grabFile(path: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: expanded) else {
            return "File not found: \(path)"
        }

        let url = URL(fileURLWithPath: expanded)
        let ext = url.pathExtension.lowercased()

        let imageExts: Set = ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff"]
        if imageExts.contains(ext) {
            return "\(url.lastPathComponent)\n[IMAGE:\(expanded)]"
        }

        let textExts: Set = [
            "txt", "md", "py", "js", "ts", "swift", "json", "yaml", "yml",
            "toml", "csv", "html", "css", "sh", "sql", "xml", "rs", "go",
            "java", "c", "cpp", "h", "rb", "php", "r", "log", "conf",
        ]

        if textExts.contains(ext) || (try? fm.attributesOfItem(atPath: expanded)[.size] as? Int ?? 0) ?? 0 < 100000 {
            if let content = try? String(contentsOfFile: expanded, encoding: .utf8) {
                let truncated = content.count > 10000 ? String(content.prefix(10000)) + "\n... (truncated)" : content
                return "File: \(url.lastPathComponent) (\(content.count) characters)\n\n\(truncated)"
            }
        }

        let size = (try? fm.attributesOfItem(atPath: expanded)[.size] as? Int) ?? 0
        return "File: \(url.lastPathComponent) (\(size) bytes) — binary format, cannot display as text."
    }
}
