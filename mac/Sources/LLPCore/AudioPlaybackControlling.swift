import Foundation

public protocol AudioPlaybackControlling: AnyObject {
    var onFinish: ((Bool) -> Void)? { get set }
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var isPlaying: Bool { get }

    var playbackSpeed: PlaybackSpeed { get }
    func setPlaybackSpeed(_ speed: PlaybackSpeed) throws

    func load(url: URL) throws
    func play()
    func pause()
    func stop()
}
