import AppKit
import SwiftUI

/// NSViewRepresentable that captures scroll wheel and magnify events for the canvas.
/// Replaces SwiftUI's DragGesture for pan — this gives us native trackpad momentum,
/// cursor-anchored zoom, and eliminates gesture conflicts with node dragging.
struct CanvasScrollHandler: NSViewRepresentable {
    var onPan: (CGFloat, CGFloat) -> Void
    var onZoom: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> CanvasScrollNSView {
        let view = CanvasScrollNSView()
        view.onPan = onPan
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: CanvasScrollNSView, context: Context) {
        nsView.onPan = onPan
        nsView.onZoom = onZoom
    }
}

/// Custom NSView that intercepts scroll wheel events.
/// - Trackpad two-finger scroll (phase-based) → pan with native momentum
/// - Mouse scroll wheel (discrete, no phase) → zoom toward cursor
/// - Cmd+scroll → zoom toward cursor (both trackpad and mouse)
final class CanvasScrollNSView: NSView {
    var onPan: ((CGFloat, CGFloat) -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let isTrackpad = event.phase != [] || event.momentumPhase != []
        let cmdHeld = event.modifierFlags.contains(.command)

        if cmdHeld || !isTrackpad {
            // Zoom toward cursor
            let locationInView = convert(event.locationInWindow, from: nil)
            // Positive deltaY = scroll up = zoom in
            let zoomDelta = event.scrollingDeltaY
            let factor: CGFloat
            if event.hasPreciseScrollingDeltas {
                // Trackpad — smooth, continuous
                factor = 1.0 + zoomDelta * 0.004
            } else {
                // Mouse wheel — discrete clicks
                factor = zoomDelta > 0 ? 1.08 : 0.92
            }
            onZoom?(factor, locationInView)
        } else {
            // Trackpad pan — includes momentum phases automatically
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            onPan?(dx, dy)
        }
    }

    override func magnify(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        let factor = 1.0 + event.magnification
        onZoom?(factor, locationInView)
    }

    // Pass through mouse events so SwiftUI handles clicks/drags on nodes
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only intercept scroll and magnify — let everything else pass through
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .scrollWheel, .magnify:
            return self
        default:
            return nil
        }
    }
}
