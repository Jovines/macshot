import Cocoa
import XCTest

@MainActor
final class ToolbarDraggingTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 800, height: 600)

    func testBottomBarKeepsItsWiderOptionsOnscreen() {
        let point = ToolbarPlacement.origin(NSPoint(x: -200, y: -200),
            barSize: NSSize(width: 200, height: 40),
            optionsSize: NSSize(width: 400, height: 36), bounds: screen)
        XCTAssertEqual(point, NSPoint(x: 104, y: 42))
    }

    func testEditorOptionsAboveTheBarStayOnscreen() {
        let point = ToolbarPlacement.origin(NSPoint(x: 1000, y: 1000),
            barSize: NSSize(width: 200, height: 40),
            optionsSize: NSSize(width: 400, height: 36),
            optionsAbove: true, bounds: screen)
        XCTAssertEqual(point, NSPoint(x: 496, y: 518))
    }

    func testActionBarAvoidsTheNotchOnAnOffsetDisplay() {
        let point = ToolbarPlacement.origin(NSPoint(x: -420, y: 550),
            barSize: NSSize(width: 40, height: 100),
            bounds: NSRect(x: -800, y: 0, width: 800, height: 600),
            obstructions: [NSRect(x: -450, y: 570, width: 100, height: 30)])
        XCTAssertEqual(point, NSPoint(x: -420, y: 468))
    }

    func testBothGripsAreSeparateFromButtonsAndSurviveRebuilds() {
        for orientation in [ToolbarStripView.Orientation.horizontal, .vertical] {
            let parent = NSView(frame: screen)
            let strip = ToolbarStripView(orientation: orientation)
            parent.addSubview(strip)
            let buttons = [ToolbarButton(action: .copy, sfSymbol: "doc.on.doc", tooltip: "Copy")]
            strip.setButtons(buttons)
            strip.passesThrough = true // Editor gaps must still let the grip receive events.
            let center = NSPoint(x: strip.dragHandle.frame.midX, y: strip.dragHandle.frame.midY)
            XCTAssertTrue(strip.hitTest(center) === strip.dragHandle)
            XCTAssertFalse(strip.dragHandle.frame.intersects(strip.buttonViews[0].frame))
            strip.setButtons(buttons + buttons)
            XCTAssertTrue(strip.dragHandle.superview === strip)
            XCTAssertFalse(strip.dragHandle.frame.intersects(strip.buttonViews[0].frame))
        }
    }

    func testGripDragIsStableWhenTheHandleMovesAndDoubleClickResets() throws {
        let grip = ToolbarDragHandleView()
        var began = 0, reset = 0
        var points: [NSPoint] = []
        grip.onBegin = { began += 1 }
        grip.onDrag = { start, current in
            XCTAssertEqual(start, NSPoint(x: 100, y: 100))
            points.append(current)
        }
        grip.onReset = { reset += 1 }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint, clicks: Int = 1) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                clickCount: clicks, pressure: 1))
        }
        grip.mouseDown(with: try mouse(.leftMouseDown, NSPoint(x: 100, y: 100)))
        grip.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: 120, y: 130)))
        grip.frame.origin = NSPoint(x: 20, y: 30)
        grip.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: 140, y: 160)))
        grip.mouseUp(with: try mouse(.leftMouseUp, NSPoint(x: 140, y: 160)))
        grip.mouseDragged(with: try mouse(.leftMouseDragged, .zero))
        grip.mouseDown(with: try mouse(.leftMouseDown, .zero, clicks: 2))
        XCTAssertEqual(began, 1)
        XCTAssertEqual(reset, 1)
        XCTAssertEqual(points, [NSPoint(x: 120, y: 130), NSPoint(x: 140, y: 160)])
    }
}
