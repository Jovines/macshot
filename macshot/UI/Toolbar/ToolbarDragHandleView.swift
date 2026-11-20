import Cocoa

/// A dedicated grip keeps moving chrome separate from drawing or moving a capture.
final class ToolbarDragHandleView: NSView {
    var vertical = false
    var tintColor: NSColor = .secondaryLabelColor
    var onBegin: (() -> Void)?
    var onDrag: ((NSPoint, NSPoint) -> Void)?
    var onReset: (() -> Void)?
    private var startPoint: NSPoint?

    override func draw(_ dirtyRect: NSRect) {
        tintColor.withAlphaComponent(0.65).setFill()
        for a in [-2.0, 2.0] {
            for b in [-4.0, 0.0, 4.0] {
                let offset = vertical ? NSPoint(x: b, y: a) : NSPoint(x: a, y: b)
                NSBezierPath(ovalIn: NSRect(x: bounds.midX + offset.x - 1,
                                           y: bounds.midY + offset.y - 1,
                                           width: 2, height: 2)).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            startPoint = nil
            onReset?()
            return
        }
        startPoint = screenPoint(for: event)
        onBegin?()
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        onDrag?(startPoint, screenPoint(for: event))
        NSCursor.closedHand.set()
    }

    override func mouseUp(with event: NSEvent) {
        startPoint = nil
        NSCursor.openHand.set()
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
