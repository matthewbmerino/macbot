import Foundation

enum ChartTools {
    static let generateChartSpec = ToolSpec(
        name: "generate_chart",
        description: "Generate a chart image using matplotlib. Write Python code that creates a plot and calls plt.savefig(OUTPUT_PATH). The chart is styled with a dark theme automatically. Use matplotlib.pyplot as plt. Do NOT call plt.show().",
        properties: [
            "code": .init(type: "string", description: "Python matplotlib code. Use plt from matplotlib.pyplot. Call plt.savefig(OUTPUT_PATH) at the end. Example: plt.plot([1,2,3], [10,20,15]); plt.title('My Chart'); plt.savefig(OUTPUT_PATH)"),
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
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
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
        'grid.alpha': 0.5,
        'figure.figsize': (12, 7),
        'font.size': 12,
        'axes.grid': True,
    })
    OUTPUT_PATH = '%OUTPUT_PATH%'
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
        let chartId = UUID().uuidString.prefix(8)
        let chartPath = "/tmp/macbot_chart_\(chartId).png"

        // Inject theme with output path, then append user code
        let themedSetup = chartTheme.replacingOccurrences(of: "%OUTPUT_PATH%", with: chartPath)

        // Ensure the user code calls plt.savefig(OUTPUT_PATH)
        // If they forgot, append it
        var userCode = code
        if !userCode.contains("savefig") {
            userCode += "\nplt.tight_layout()\nplt.savefig(OUTPUT_PATH, dpi=150, bbox_inches='tight')"
        }

        let fullCode = """
        \(themedSetup)

        \(userCode)

        plt.close('all')
        print('OK')
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

            let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if FileManager.default.fileExists(atPath: chartPath) {
                return "\(title)\n[IMAGE:\(chartPath)]"
            }

            // Provide actionable error
            var errorMsg = "Chart generation failed."
            if stderr.contains("No module named") {
                let module = stderr.components(separatedBy: "No module named").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "'", with: "") ?? "unknown"
                errorMsg += " Missing Python module: \(module). Install with: pip3 install \(module)"
            } else if !stderr.isEmpty {
                errorMsg += " \(String(stderr.prefix(500)))"
            }
            if !stdout.isEmpty && !stdout.contains("OK") {
                errorMsg += " stdout: \(String(stdout.prefix(200)))"
            }

            return errorMsg
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
