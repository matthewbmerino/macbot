import Foundation

enum ChartTools {
    static let generateChartSpec = ToolSpec(
        name: "generate_chart",
        description: "Generate a professional chart using Plotly. Use for any data visualization: bar, line, pie, scatter, candlestick, etc. Write Plotly Python code. The chart will be styled with a modern dark theme automatically.",
        properties: [
            "code": .init(type: "string", description: "Plotly Python code. Create a fig object. Do NOT call fig.show(). Example: fig = px.bar(x=['A','B'], y=[10,20])"),
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

    private static let chartTheme = """
    fig.update_layout(
        template='plotly_dark',
        paper_bgcolor='#0a0a0a',
        plot_bgcolor='#0a0a0a',
        font=dict(family='SF Pro Display, -apple-system, Helvetica Neue, sans-serif', color='#e8e8e8'),
        title_font=dict(size=18, color='#e8e8e8'),
        margin=dict(l=60, r=40, t=60, b=50),
        colorway=['#6366f1', '#22c55e', '#f59e0b', '#ef4444', '#06b6d4', '#ec4899', '#8b5cf6', '#14b8a6'],
        xaxis=dict(gridcolor='#1e1e1e', zerolinecolor='#2a2a2a'),
        yaxis=dict(gridcolor='#1e1e1e', zerolinecolor='#2a2a2a'),
    )
    """

    static func register(on registry: ToolRegistry) async {
        await registry.register(generateChartSpec) { args in
            await generateChart(code: args["code"] as? String ?? "", title: args["title"] as? String ?? "Chart")
        }
        await registry.register(grabFileSpec) { args in
            grabFile(path: args["path"] as? String ?? "")
        }
    }

    static func generateChart(code: String, title: String) async -> String {
        let chartPath = "/tmp/macbot_chart.png"

        let fullCode = """
        import plotly.graph_objects as go
        import plotly.express as px
        import numpy as np

        \(code)

        \(chartTheme)

        fig.write_image('\(chartPath)', width=1200, height=700, scale=2)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", fullCode]
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
                return "Error: chart generation timed out"
            }

            if FileManager.default.fileExists(atPath: chartPath) {
                return "\(title)\n[IMAGE:\(chartPath)]"
            }

            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return "Chart generation failed: \(err)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    static func grabFile(path: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: expanded) else {
            return "File not found: \(path)"
        }

        let url = URL(fileURLWithPath: expanded)
        let ext = url.pathExtension.lowercased()

        // Images — display inline
        let imageExts: Set = ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff"]
        if imageExts.contains(ext) {
            return "\(url.lastPathComponent)\n[IMAGE:\(expanded)]"
        }

        // Text files — show content
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
