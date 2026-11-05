import XCTest
@testable import LLPCore
@testable import LLP

final class PlaybackSpeedTests: XCTestCase {
    func testOptionsMatchDisplayedMultipliers() {
        XCTAssertEqual(PlaybackSpeed.allCases.map(\.title), ["0.5X", "1X", "2X"])
        XCTAssertEqual(PlaybackSpeed.allCases.map(\.rawValue), [0.5, 1, 2])
        XCTAssertEqual(PlaybackSpeedSelection().speed, .normal)
    }

    func testEverySelectionAppliesExactRateBeforeCommitting() {
        var selection = PlaybackSpeedSelection()
        var applied: [Float] = []
        for speed in PlaybackSpeed.allCases {
            selection.select(speed) { applied.append($0) }
            XCTAssertEqual(selection.speed, speed)
        }
        XCTAssertEqual(applied, [0.5, 1, 2])
    }

    func testRejectedChangePreservesLastAcceptedSelection() {
        struct Rejected: Error {}
        var selection = PlaybackSpeedSelection()
        selection.select(.half) { _ in }
        XCTAssertThrowsError(try selection.select(.double) { _ in throw Rejected() })
        XCTAssertEqual(selection.speed, .half)
        selection.select(.double) { _ in }
        XCTAssertEqual(selection.speed, .double)
    }

    func testEachPlaybackStartResetsSelectionAndEngineRate() {
        for speed in PlaybackSpeed.allCases {
            var selection = PlaybackSpeedSelection()
            selection.select(speed) { _ in }
            var rate: Float = 0
            selection.start { rate = $0 }
            XCTAssertEqual(rate, 1)
            XCTAssertEqual(selection.speed, .normal)
        }
    }

    func testControllerRejectsSpeedWithoutMediaAndDoesNotStartPlayback() {
        let controller = AVAudioPlaybackController()
        for speed in PlaybackSpeed.allCases {
            XCTAssertThrowsError(try controller.setPlaybackSpeed(speed)) { error in
                guard case AVAudioPlaybackController.SpeedError.mediaNotReady = error else {
                    return XCTFail("Expected mediaNotReady")
                }
            }
            XCTAssertEqual(controller.playbackSpeed, .normal)
            XCTAssertFalse(controller.isPlaying)
        }
        controller.play()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.playbackSpeed, .normal)
    }
}
