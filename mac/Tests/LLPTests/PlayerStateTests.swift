import XCTest
@testable import LLPCore

final class PlayerStateTests: XCTestCase {
    func testLoadTrackResetsMarkersAndReplayState() {
        var state = PlayerState(duration: 100, startMarker: 10, endMarker: 20, isReplayingSegment: true)

        state.loadTrack(duration: 50)

        XCTAssertEqual(state.duration, 50)
        XCTAssertNil(state.startMarker)
        XCTAssertNil(state.endMarker)
        XCTAssertFalse(state.isReplayingSegment)
    }

    func testUsesFullTrackWhenMarkersAreNotSet() throws {
        let state = PlayerState(duration: 42)
        let segment = try XCTUnwrap(state.segment)

        XCTAssertEqual(segment.start, 0)
        XCTAssertEqual(segment.end, 42)
    }

    func testSetStartClampsToDuration() {
        var state = PlayerState(duration: 90)

        state.apply(.setStart(120))

        XCTAssertEqual(state.startMarker, 90)
    }

    func testSetEndBeforeExistingStartClearsStartMarker() {
        var state = PlayerState(duration: 90)

        state.apply(.setStart(40))
        state.apply(.setEnd(30))

        XCTAssertNil(state.startMarker)
        XCTAssertEqual(state.endMarker, 30)
    }

    func testSetStartAfterExistingEndClearsEndMarker() {
        var state = PlayerState(duration: 90)

        state.apply(.setEnd(30))
        state.apply(.setStart(40))

        XCTAssertEqual(state.startMarker, 40)
        XCTAssertNil(state.endMarker)
    }

    func testZeroDurationTrackDoesNotExposeSegment() {
        let state = PlayerState(duration: 0)

        XCTAssertNil(state.segment)
    }

    func testSegmentReplayStateCanBeginAndEnd() {
        var state = PlayerState(duration: 10)

        state.beginSegmentReplay()
        XCTAssertTrue(state.isReplayingSegment)

        state.endSegmentReplay()
        XCTAssertFalse(state.isReplayingSegment)
    }

    func testCannotBeginSegmentReplayWithoutAPlayableSegment() {
        var state = PlayerState(duration: 0)

        state.beginSegmentReplay()

        XCTAssertFalse(state.isReplayingSegment)
    }

    func testMarkerChangesEndActiveSegmentReplay() {
        var state = PlayerState(duration: 90, isReplayingSegment: true)

        state.apply(.setStart(10))

        XCTAssertFalse(state.isReplayingSegment)
    }

    func testMoveSelectedSegmentForwardPreservesLength() {
        var state = PlayerState(duration: 90, startMarker: 10, endMarker: 25)

        let didMove = state.moveSelectedSegmentForward()

        XCTAssertTrue(didMove)
        XCTAssertEqual(state.startMarker, 25)
        XCTAssertEqual(state.endMarker, 40)
    }

    func testMoveSelectedSegmentBackwardPreservesLength() {
        var state = PlayerState(duration: 90, startMarker: 30, endMarker: 45)

        let didMove = state.moveSelectedSegmentBackward()

        XCTAssertTrue(didMove)
        XCTAssertEqual(state.startMarker, 15)
        XCTAssertEqual(state.endMarker, 30)
    }

    func testMoveSelectedSegmentForwardClampsToEndOfTrack() {
        var state = PlayerState(duration: 90, startMarker: 65, endMarker: 80)

        let didMove = state.moveSelectedSegmentForward()

        XCTAssertTrue(didMove)
        XCTAssertEqual(state.startMarker, 75)
        XCTAssertEqual(state.endMarker, 90)
    }

    func testMoveSelectedSegmentBackwardClampsToStartOfTrack() {
        var state = PlayerState(duration: 90, startMarker: 10, endMarker: 25)

        let didMove = state.moveSelectedSegmentBackward()

        XCTAssertTrue(didMove)
        XCTAssertEqual(state.startMarker, 0)
        XCTAssertEqual(state.endMarker, 15)
    }

    func testMoveSelectedSegmentRequiresExplicitStartAndEndMarkers() {
        var state = PlayerState(duration: 90, startMarker: 10)

        let didMove = state.moveSelectedSegmentForward()

        XCTAssertFalse(didMove)
        XCTAssertEqual(state.startMarker, 10)
        XCTAssertNil(state.endMarker)
    }

    func testMoveSelectedSegmentReturnsFalseAtTrackBoundary() {
        var state = PlayerState(duration: 90, startMarker: 75, endMarker: 90)

        let didMove = state.moveSelectedSegmentForward()

        XCTAssertFalse(didMove)
        XCTAssertEqual(state.startMarker, 75)
        XCTAssertEqual(state.endMarker, 90)
    }

    func testMoveSelectedSegmentEndsActiveSegmentReplay() {
        var state = PlayerState(duration: 90, startMarker: 10, endMarker: 25, isReplayingSegment: true)

        state.moveSelectedSegmentForward()

        XCTAssertFalse(state.isReplayingSegment)
    }
}
