import Foundation
import AppKit

@MainActor
@Observable
final class GhostCursorViewModel {
    var steps: [GhostStep] = []
    var currentStepIndex: Int = 0
    var isRunning: Bool = false
    var narration: String = ""
    var isCancelled: Bool = false

    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(currentStepIndex) / Double(steps.count)
    }

    var currentStepLabel: String {
        guard !steps.isEmpty, currentStepIndex < steps.count else { return "" }
        return "Step \(currentStepIndex + 1)/\(steps.count): \(steps[currentStepIndex].description)"
    }

    func cancel() {
        isCancelled = true
        isRunning = false
        narration = "Cancelled."
    }

    func execute(parsedSteps: [GhostStep]) async {
        guard AccessibilityBridge.checkAccessibilityPermission() else {
            narration = "Accessibility permission required. Opening System Settings..."
            AccessibilityBridge.requestAccessibilityPermission()
            return
        }

        steps = parsedSteps
        currentStepIndex = 0
        isRunning = true
        isCancelled = false

        for (index, step) in steps.enumerated() {
            guard !isCancelled else { break }
            currentStepIndex = index
            steps[index].status = .running
            narration = step.description

            let success = await executeStep(step)
            steps[index].status = success ? .completed : .failed

            if !success {
                narration = "Step failed: \(step.description)"
                break
            }

            // Pause between steps for visual clarity
            try? await Task.sleep(for: .milliseconds(300))
        }

        if !isCancelled && steps.allSatisfy({ $0.status == .completed }) {
            narration = "All steps completed."
        }
        isRunning = false
    }

    // MARK: - Step Execution

    private func executeStep(_ step: GhostStep) async -> Bool {
        switch step.action {
        case .openApp:
            return await openApp(step.app)

        case .click(let elementLabel):
            return await executeClick(app: step.app, label: elementLabel)

        case .type(let text):
            // Make sure the target app is focused before typing
            await focusApp(step.app)
            try? await Task.sleep(for: .milliseconds(200))
            AccessibilityBridge.typeText(text)
            return true

        case .menu(let path):
            await focusApp(step.app)
            try? await Task.sleep(for: .milliseconds(200))
            return AccessibilityBridge.navigateMenu(app: step.app, path: path)

        case .shortcut(let keys):
            guard !keys.isEmpty else { return true }
            await focusApp(step.app)
            try? await Task.sleep(for: .milliseconds(200))
            AccessibilityBridge.performKeyPress(keys)
            return true

        case .search(let query):
            return await executeSearch(app: step.app, query: query)

        case .wait(let seconds):
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            return true
        }
    }

    // MARK: - App Management

    private func openApp(_ name: String) async -> Bool {
        // Try to activate if already running
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == name.lowercased()
        }) {
            app.activate()
            await waitForFrontmost(pid: app.processIdentifier)
            return true
        }

        // Launch via NSWorkspace
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        let paths = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app",
            "/Applications/Utilities/\(name).app",
        ]

        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            narration = "Could not find app: \(name)"
            return false
        }

        do {
            let launched = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path), configuration: config
            )
            await waitForFrontmost(pid: launched.processIdentifier)
            // Extra settle time for newly launched apps
            try? await Task.sleep(for: .seconds(1.5))
            return true
        } catch {
            narration = "Failed to open \(name): \(error.localizedDescription)"
            return false
        }
    }

    private func executeSearch(app: String, query: String) async -> Bool {
        await focusApp(app)
        // Extra time for browser to be fully ready
        try? await Task.sleep(for: .milliseconds(500))

        // Cmd+L focuses the address bar in all major browsers
        AccessibilityBridge.performKeyPress("Cmd+l")
        try? await Task.sleep(for: .milliseconds(400))

        // Select all existing text, then type the query
        AccessibilityBridge.performKeyPress("Cmd+a")
        try? await Task.sleep(for: .milliseconds(100))

        // Type the search query character by character
        AccessibilityBridge.typeText(query)
        try? await Task.sleep(for: .milliseconds(200))

        // Hit Enter to search
        AccessibilityBridge.performKeyPress("return")
        return true
    }

    private func executeClick(app: String, label: String) async -> Bool {
        await focusApp(app)
        try? await Task.sleep(for: .milliseconds(300))

        guard let element = AccessibilityBridge.findElement(app: app, label: label),
              let center = AccessibilityBridge.elementCenter(element) else {
            narration = "Could not find '\(label)' in \(app)"
            return false
        }

        await GhostCursorController.shared.animateTo(center)
        AccessibilityBridge.performClick(at: center)
        return true
    }

    // MARK: - Focus Management

    /// Focus an app and wait until macOS confirms it's frontmost.
    /// Uses async sleep instead of Thread.sleep to avoid blocking MainActor.
    private func focusApp(_ name: String) async {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == name.lowercased()
        }) else { return }

        app.activate()
        await waitForFrontmost(pid: app.processIdentifier)
    }

    /// Poll until the given PID is the frontmost app, or timeout.
    /// Uses async sleep so we don't block the MainActor.
    private func waitForFrontmost(pid: pid_t) async {
        for _ in 0..<40 {  // 40 * 50ms = 2 seconds max
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
