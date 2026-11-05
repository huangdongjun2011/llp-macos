import XCTest
@testable import LLPCore

final class LoopSegmentTests: XCTestCase {
    func testCreatesSegmentWhenStartIsBeforeEnd() {
        let segment = LoopSegment(start: 10, end: 20, duration: 60)

        XCTAssertEqual(segment, LoopSegment(start: 10, end: 20, duration: 60))
    }

    func testRejectsEmptyOrReversedSegment() {
        XCTAssertNil(LoopSegment(start: 20, end: 20, duration: 60))
        XCTAssertNil(LoopSegment(start: 30, end: 20, duration: 60))
    }

    func testClampsMarkersToTrackDuration() {
        let segment = LoopSegment(start: -10, end: 90, duration: 60)

        XCTAssertEqual(segment?.start, 0)
        XCTAssertEqual(segment?.end, 60)
    }

    func testRejectsInvalidDurationsAndNonFiniteMarkers() {
        XCTAssertNil(LoopSegment(start: 0, end: 1, duration: 0))
        XCTAssertNil(LoopSegment(start: .nan, end: 1, duration: 10))
        XCTAssertNil(LoopSegment(start: 0, end: .infinity, duration: 10))
    }

    func testDetectsWhenPlaybackShouldRestart() throws {
        let segment = try XCTUnwrap(LoopSegment(start: 5, end: 15, duration: 30))

        XCTAssertFalse(segment.shouldRestart(at: 14.99))
        XCTAssertTrue(segment.shouldRestart(at: 15))
        XCTAssertTrue(segment.shouldRestart(at: 16))
    }
}
