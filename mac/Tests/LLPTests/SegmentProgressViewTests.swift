import AppKit
import XCTest
@testable import LLP
import LLPCore

@MainActor
final class SegmentProgressViewTests: XCTestCase {
    private func makeView() -> SegmentProgressView {
        let view = SegmentProgressView(frame: NSRect(x: 0, y: 0, width: 214, height: 44))
        view.duration = 100
        view.startMarker = 50
        view.endMarker = 50
        return view
    }

    func testTrackAndMarkersFitWithSeparateGaps() {
        let view = makeView()
        let track = view.trackRect()
        XCTAssertEqual(track.height, 10)
        XCTAssertEqual(view.intrinsicContentSize.height, view.bounds.height)
        for x in [track.minX, track.midX, track.maxX] {
            let start = view.handleRect(at: x, pointsUp: true)
            let end = view.handleRect(at: x, pointsUp: false)
            XCTAssertEqual(track.minY - start.maxY, 4)
            XCTAssertEqual(end.minY - track.maxY, 4)
            XCTAssertTrue(view.bounds.contains(start))
            XCTAssertTrue(view.bounds.contains(end))
        }
    }

    func testTrianglesPointTowardTrack() {
        let view = makeView()
        for pointsUp in [true, false] {
            let rect = view.handleRect(at: 107, pointsUp: pointsUp)
            let path = view.handlePath(at: 107, pointsUp: pointsUp)
            var point = NSPoint.zero
            XCTAssertEqual(path.element(at: 0, associatedPoints: &point), .moveTo)
            XCTAssertEqual(point, NSPoint(x: 107, y: pointsUp ? rect.maxY : rect.minY))
            XCTAssertEqual(path.element(at: 1, associatedPoints: &point), .lineTo)
            XCTAssertEqual(point.y, pointsUp ? rect.minY : rect.maxY)
        }
    }

    func testTrackClicksSeekEvenAtOverlappingMarkersAndEndpoints() {
        let view = makeView()
        var seeks: [TimeInterval] = []
        view.onSeek = { seeks.append($0) }
        view.onMarkerChange = { _ in XCTFail("Track clicks must not move markers") }
        for x in [CGFloat(7), 107, 207] {
            view.mouseDown(with: event(.leftMouseDown, x: x, y: 22))
            view.mouseUp(with: event(.leftMouseUp, x: x, y: 22))
        }
        XCTAssertEqual(seeks, [0, 0, 50, 50, 100, 100])
    }

    func testEachOverlappingMarkerCanBeDraggedAndClampsOutsideTrack() {
        let view = makeView()
        var starts: [TimeInterval] = []
        var ends: [TimeInterval] = []
        view.onSeek = { _ in XCTFail("Marker drags must not seek") }
        view.onMarkerChange = { update in
            switch update {
            case .setStart(let time): starts.append(time)
            case .setEnd(let time): ends.append(time)
            }
        }
        view.mouseDown(with: event(.leftMouseDown, x: 107, y: 9))
        view.mouseDragged(with: event(.leftMouseDragged, x: -20, y: 22))
        view.mouseUp(with: event(.leftMouseUp, x: -20, y: 22))
        view.mouseDown(with: event(.leftMouseDown, x: 107, y: 35))
        view.mouseDragged(with: event(.leftMouseDragged, x: 250, y: 22))
        view.mouseUp(with: event(.leftMouseUp, x: 250, y: 22))
        XCTAssertEqual(starts, [50, 0, 0])
        XCTAssertEqual(ends, [50, 100, 100])
    }

    func testGapClicksSeekAndPlayheadDragKeepsItsTarget() {
        let view = makeView()
        var seeks: [TimeInterval] = []
        view.onSeek = { seeks.append($0) }
        view.onMarkerChange = { _ in XCTFail("Gap clicks must not move markers") }
        for y in [CGFloat(15), 29] {
            view.mouseDown(with: event(.leftMouseDown, x: 107, y: y))
            view.mouseDragged(with: event(.leftMouseDragged, x: 207, y: 35))
            view.mouseUp(with: event(.leftMouseUp, x: 207, y: 35))
        }
        XCTAssertEqual(seeks, [50, 100, 100, 50, 100, 100])
    }

    func testZeroDurationDoesNotSeekOrChangeMarkers() {
        let view = makeView()
        view.duration = 0
        view.onSeek = { _ in XCTFail("Empty tracks must not seek") }
        view.onMarkerChange = { _ in XCTFail("Empty tracks must not change markers") }
        view.mouseDown(with: event(.leftMouseDown, x: 107, y: 22))
        view.mouseDragged(with: event(.leftMouseDragged, x: 207, y: 22))
        view.mouseUp(with: event(.leftMouseUp, x: 207, y: 22))
    }

    private func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1
        )!
    }
}
