import XCTest
@testable import LLPCore

final class AudioPlaylistTests: XCTestCase {
    private let tracks = [URL(fileURLWithPath: "/one.mp3"), URL(fileURLWithPath: "/two.wav")]

    func testOpenAndSelectStartAtZeroAndPlayIncludingReselection() throws {
        let playback = FakeAudioPlayback()
        let playlist = AudioPlaylist(playback: playback)
        try playlist.open(tracks)
        XCTAssertEqual(playlist.files, tracks)
        XCTAssertEqual(playlist.currentIndex, 0)
        XCTAssertTrue(playback.isPlaying)
        playback.currentTime = 12
        try playlist.select(1)
        XCTAssertEqual(playback.loadedURL, tracks[1])
        XCTAssertEqual(playlist.currentIndex, 1)
        XCTAssertEqual(playback.currentTime, 0)
        playback.currentTime = 8
        try playlist.select(1)
        XCTAssertEqual(playback.currentTime, 0)
        XCTAssertTrue(playback.isPlaying)
    }

    func testCompletionLoadsNextPausedAndDoesNotWrapAtEnd() throws {
        let playback = FakeAudioPlayback()
        let playlist = AudioPlaylist(playback: playback)
        try playlist.open(tracks)
        XCTAssertTrue(try playlist.advanceAfterFinishing())
        XCTAssertEqual(playlist.currentIndex, 1)
        XCTAssertEqual(playback.loadedURL, tracks[1])
        XCTAssertEqual(playback.currentTime, 0)
        XCTAssertFalse(playback.isPlaying)
        playback.play()
        XCTAssertFalse(try playlist.advanceAfterFinishing())
        XCTAssertEqual(playlist.currentIndex, 1)
        XCTAssertFalse(playback.isPlaying)
    }

    func testEmptyAndInvalidSelectionsPreserveExistingTrack() throws {
        let playback = FakeAudioPlayback()
        let playlist = AudioPlaylist(playback: playback)
        XCTAssertFalse(try playlist.advanceAfterFinishing())
        try playlist.open(tracks)
        XCTAssertThrowsError(try playlist.open([]))
        XCTAssertThrowsError(try playlist.select(-1))
        XCTAssertThrowsError(try playlist.select(2))
        XCTAssertEqual(playlist.files, tracks)
        XCTAssertEqual(playlist.currentIndex, 0)
        XCTAssertEqual(playback.loadedURL, tracks[0])
    }

    func testFailedLoadsPreservePlaylistAndCompletionRemainsPaused() throws {
        let playback = FakeAudioPlayback()
        let playlist = AudioPlaylist(playback: playback)
        try playlist.open(tracks)
        playback.failLoads = true
        XCTAssertThrowsError(try playlist.open([tracks[1]]))
        XCTAssertThrowsError(try playlist.select(1))
        XCTAssertEqual(playlist.files, tracks)
        XCTAssertEqual(playlist.currentIndex, 0)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertThrowsError(try playlist.advanceAfterFinishing())
        XCTAssertEqual(playlist.currentIndex, 0)
        XCTAssertEqual(playback.loadedURL, tracks[0])
        XCTAssertFalse(playback.isPlaying)
    }

    func testFolderDiscoveryFeedsSortedAudioIntoPlayback() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["track10.mp3", "track2.WAV", "notes.txt", ".hidden.mp3"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let nested = folder.appendingPathComponent("nested.mp3")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data().write(to: nested.appendingPathComponent("child.mp3"))
        let files = try AudioFileDiscovery.files(at: folder)
        XCTAssertEqual(files.map(\.lastPathComponent), ["track2.WAV", "track10.mp3"])
        let playback = FakeAudioPlayback()
        let playlist = AudioPlaylist(playback: playback)
        try playlist.open(files)
        XCTAssertEqual(playback.loadedURL, files[0])
        try playlist.advanceAfterFinishing()
        XCTAssertEqual(playback.loadedURL, files[1])
        XCTAssertFalse(playback.isPlaying)
    }

    func testDiscoveryHandlesSingleFileEmptyFolderNonAudioAndMissingPath() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(try AudioFileDiscovery.files(at: folder), [])
        let audio = folder.appendingPathComponent("test.mp3")
        try Data().write(to: audio)
        XCTAssertEqual(try AudioFileDiscovery.files(at: audio), [audio])
        let text = folder.appendingPathComponent("test.txt")
        try Data().write(to: text)
        XCTAssertEqual(try AudioFileDiscovery.files(at: text), [])
        XCTAssertThrowsError(try AudioFileDiscovery.files(at: folder.appendingPathComponent("missing")))
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class FakeAudioPlayback: AudioPlaybackControlling {
    var playbackSpeed: PlaybackSpeed = .normal
    func setPlaybackSpeed(_ speed: PlaybackSpeed) throws { playbackSpeed = speed }
    var onFinish: ((Bool) -> Void)?
    var duration: TimeInterval = 30
    var currentTime: TimeInterval = 0
    var isPlaying = false
    var loadedURL: URL?
    var failLoads = false

    func load(url: URL) throws {
        if failLoads { throw CocoaError(.fileReadCorruptFile) }
        loadedURL = url
        isPlaying = false
    }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false; currentTime = 0 }
}
