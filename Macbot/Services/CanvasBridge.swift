import AppKit
import Foundation

/// Singleton that lets system-wide components (hotkeys, menu bar, QuickPanel)
/// route actions to the currently-visible canvas without capturing its
/// ViewModel through the view graph.
///
/// `CanvasView` calls `register` on appear and `unregister` on disappear.
/// Callers that want to "drop a note at the user's current spot" go through
/// here; when no canvas is visible we fall back to the QuickPanel.
@MainActor
final class CanvasBridge {
    static let shared = CanvasBridge()

    private weak var activeViewModel: CanvasViewModel?

    private init() {}

    func register(_ viewModel: CanvasViewModel) {
        activeViewModel = viewModel
    }

    func unregister(_ viewModel: CanvasViewModel) {
        if activeViewModel === viewModel {
            activeViewModel = nil
        }
    }

    var hasActiveCanvas: Bool { activeViewModel != nil }

    /// Create a note at the canvas viewport center in edit mode. If no canvas
    /// is currently mounted, fall back to the QuickPanel so the thought still
    /// gets captured somewhere.
    func quickNoteFromAnywhere() {
        if let vm = activeViewModel {
            activateMainWindow()
            let view = CGPoint(x: vm.viewSize.width / 2, y: vm.viewSize.height / 2)
            let canvasPoint = vm.viewToCanvas(view)
            vm.addNode(at: canvasPoint)
        } else {
            QuickPanelController.shared.show()
        }
    }

    private func activateMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows where window.title == "macbot" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
