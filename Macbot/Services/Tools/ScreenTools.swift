import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit
import Vision

enum ScreenTools {

    // MARK: - Native Swift capture (no subprocess, no Python)

    /// Captures the main display via ScreenCaptureKit. Permission attributes
    /// to Macbot.app reliably (unlike shelling out to /usr/sbin/screencapture
    /// which can confuse TCC, especially across Xcode rebuilds).
    static func captureMainDisplay(to path: String) async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = content.displays.first else { return false }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width * 2     // Retina
            config.height = display.height * 2
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                return false
            }
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }

    /// Native Swift OCR via Vision. Much faster than the Python/PyObjC fallback.
    static func nativeOCR(imagePath: String) -> String {
        guard let image = NSImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        } catch {
            return ""
        }
    }


    static let screenOCRSpec = ToolSpec(
        name: "screen_ocr",
        description: "Capture the screen (or a specific app window) and extract all visible text using OCR. Returns extracted text and the screenshot image. Use when the user asks 'what does my screen say', 'read the error on screen', or 'what's on my screen'.",
        properties: [
            "app": .init(type: "string", description: "Optional app name to capture only that window (e.g., 'Terminal', 'Safari'). Omit for full screen."),
        ]
    )

    static let screenRegionOCRSpec = ToolSpec(
        name: "screen_region_ocr",
        description: "Let the user select a screen region interactively, then extract text from it via OCR. Use when the user wants to read a specific part of their screen.",
        properties: [:]
    )

    static func register(on registry: ToolRegistry) async {
        await registry.register(screenOCRSpec) { args in
            await screenOCR(app: args["app"] as? String)
        }
        await registry.register(screenRegionOCRSpec) { _ in
            await screenRegionOCR()
        }
    }

    // MARK: - Full Screen / App Window OCR

    static func screenOCR(app: String?) async -> String {
        let screenshotPath = "/tmp/macbot_ocr_\(UUID().uuidString.prefix(8)).png"

        // Native CoreGraphics capture — TCC permission attributes to Macbot.app
        // reliably (unlike shelling out to /usr/sbin/screencapture which can
        // confuse permission inheritance, especially across Xcode rebuilds).
        let ok = await captureMainDisplay(to: screenshotPath)

        guard ok, FileManager.default.fileExists(atPath: screenshotPath) else {
            // Distinguish between permission denial and other failures
            return """
            Error: could not capture screen. Most likely cause: Screen Recording \
            permission is missing or stale. Open System Settings → Privacy & \
            Security → Screen & System Audio Recording, find Macbot (or Xcode if \
            you're running from Xcode), toggle it OFF then ON, and quit/relaunch \
            the app. Rebuilds in Xcode can invalidate the existing TCC entry.
            """
        }

        // Native Swift Vision OCR — no Python, no subprocess
        let ocrText = nativeOCR(imagePath: screenshotPath)

        var result = ""
        if !ocrText.isEmpty {
            result += "Extracted text:\n\(ocrText)\n\n"
        } else {
            result += "OCR found no readable text on screen.\n\n"
        }
        result += "[IMAGE:\(screenshotPath)]"

        return result
    }

    // MARK: - Interactive Region OCR

    static func screenRegionOCR() async -> String {
        let screenshotPath = "/tmp/macbot_region_\(UUID().uuidString.prefix(8)).png"

        // -i = interactive selection, -s = selection mode
        _ = await shell("screencapture -i -s '\(screenshotPath)'")

        guard FileManager.default.fileExists(atPath: screenshotPath) else {
            return "Error: no region selected or screenshot failed"
        }

        let ocrText = await runVisionOCR(imagePath: screenshotPath)

        var result = ""
        if !ocrText.isEmpty {
            result += "Extracted text:\n\(ocrText)\n\n"
        }
        result += "[IMAGE:\(screenshotPath)]"

        return result
    }

    // MARK: - Vision OCR via Python

    private static func runVisionOCR(imagePath: String) async -> String {
        // Use macOS Vision framework through Python/PyObjC
        // Falls back to pytesseract if PyObjC unavailable
        let code = """
        import sys

        text = ""

        # Try macOS Vision framework (PyObjC)
        try:
            import Quartz
            from Foundation import NSURL
            import Vision

            image_url = NSURL.fileURLWithPath_('\(imagePath)')
            image_source = Quartz.CGImageSourceCreateWithURL(image_url, None)
            if image_source:
                image = Quartz.CGImageSourceCreateImageAtIndex(image_source, 0, None)
                if image:
                    request = Vision.VNRecognizeTextRequest.alloc().init()
                    request.setRecognitionLevel_(1)  # Accurate
                    request.setUsesLanguageCorrection_(True)
                    handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(image, None)
                    success, error = handler.performRequests_error_([request], None)
                    if success and request.results():
                        lines = []
                        for observation in request.results():
                            candidate = observation.topCandidates_(1)
                            if candidate:
                                lines.append(candidate[0].string())
                        text = '\\n'.join(lines)
        except ImportError:
            pass
        except Exception as e:
            print(f"Vision OCR error: {e}", file=sys.stderr)

        # Fallback: pytesseract
        if not text:
            try:
                from PIL import Image
                import pytesseract
                img = Image.open('\(imagePath)')
                text = pytesseract.image_to_string(img)
            except ImportError:
                pass
            except Exception as e:
                print(f"Tesseract error: {e}", file=sys.stderr)

        print(text.strip() if text else "")
        """

        let result = await ExecutorTools.runPython(code: code)
        // Filter out STDERR lines
        let lines = result.components(separatedBy: "\n")
        let textLines = lines.filter { !$0.hasPrefix("STDERR:") && !$0.hasPrefix("Error:") }
        return textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private static func shell(_ command: String) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            if process.isRunning { process.terminate() }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func runAppleScript(_ script: String) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}
