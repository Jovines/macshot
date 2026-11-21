import Cocoa
import XCTest

/// Hiding annotation tools leaves the unified toolbar's capture actions accessible.
@MainActor
final class HideBottomToolbarTests: XCTestCase {

    private func settings(hidden: Bool) -> [String: Any?] {
        [
            "captureSnapMode": OverlayView.SnapMode.off.rawValue,
            OverlayView.hideBottomToolbarKey: hidden,
        ]
    }

    private func makeSelectedOverlay() -> OverlayView {
        let view = OverlayView()
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.screenshotImage = ImageProbe.quadrantImage(width: 800, height: 600)
        let start = NSPoint(x: 200, y: 200), end = NSPoint(x: 600, y: 450)
        view.mouseDown(with: mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: mouse(.leftMouseDragged, at: end))
        view.mouseUp(with: mouse(.leftMouseUp, at: end))
        XCTAssertEqual(view.state, .selected)
        XCTAssertTrue(view.showToolbars)
        return view
    }

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: 0, context: nil, eventNumber: 0,
                                             clickCount: 1, pressure: 1) else {
            fatalError("could not synthesize \(type)")
        }
        return event
    }

    private func strip(_ view: OverlayView, _ orientation: ToolbarStripView.Orientation) -> ToolbarStripView? {
        view.subviews.compactMap { $0 as? ToolbarStripView }.first { $0.orientation == orientation }
    }

    private func optionsRow(_ view: OverlayView) -> ToolOptionsRowView? {
        view.subviews.compactMap { $0 as? ToolOptionsRowView }.first
    }

    func testTheBottomToolbarShowsByDefault() {
        withDefaults(settings(hidden: false)) {
            let view = makeSelectedOverlay()
            XCTAssertEqual(strip(view, .horizontal)?.isHidden, false)
            XCTAssertNil(strip(view, .vertical))
        }
    }

    func testTheSettingHidesTheBottomToolbarButKeepsTheActions() {
        withDefaults(settings(hidden: true)) {
            let view = makeSelectedOverlay()
            let actions = strip(view, .horizontal)?.buttonViews.map(\.action) ?? []
            XCTAssertTrue(actions.contains(.copy))
            XCTAssertTrue(actions.contains(.save))
            XCTAssertFalse(actions.contains { if case .tool = $0 { return true }; return false })
        }
    }

    func testToolOptionsOpenOnDemandAndCloseWithoutMovingTheToolbar() {
        withDefaults(settings(hidden: false)) {
            let view = makeSelectedOverlay()
            view.handleToolbarAction(.tool(.rectangle))
            let frame = strip(view, .horizontal)?.frame
            XCTAssertEqual(optionsRow(view)?.isHidden, true)
            view.handleToolbarAction(.toolOptions)
            XCTAssertEqual(optionsRow(view)?.isHidden, false)
            XCTAssertEqual(strip(view, .horizontal)?.frame, frame)
            view.handleToolbarAction(.toolOptions)
            XCTAssertEqual(optionsRow(view)?.isHidden, true)
        }
    }

    func testTheOptionsRowStaysHiddenWhenAToolShortcutPicksATool() {
        withDefaults(settings(hidden: true)) {
            let view = makeSelectedOverlay()
            view.keyDown(with: TestKeyEvent.keyDown(characters: "r", keyCode: 15))
            XCTAssertEqual(view.currentTool, .rectangle, "tool shortcuts still work")
            view.rebuildToolbarLayout()
            XCTAssertFalse(strip(view, .horizontal)?.buttonViews.contains { $0.action == .toolOptions } ?? false)
            XCTAssertNotEqual(optionsRow(view)?.isHidden, false)
        }
    }
}
