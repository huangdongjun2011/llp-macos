import AVFoundation
import Foundation
import LLPCore

final class AVAudioPlaybackController: NSObject, AudioPlaybackControlling {
    var onFinish: ((Bool) -> Void)?
    let player = AVPlayer()
    private var speedSelection = PlaybackSpeedSelection()
    var playbackSpeed: PlaybackSpeed { speedSelection.speed }

    enum SpeedError: Error { case mediaNotReady, unsupportedSpeed }

    func setPlaybackSpeed(_ speed: PlaybackSpeed) throws {
        do {
            guard let item = player.currentItem, item.status == .readyToPlay else {
                throw SpeedError.mediaNotReady
            }
            // Ready AVPlayerItems support rates from 1 through 2; slow playback is optional.
            guard speed == .normal || (speed == .half && item.canPlaySlowForward)
                || speed == .double else {
                throw SpeedError.unsupportedSpeed
            }
            speedSelection.select(speed) { rate in
                if player.rate != 0 { player.rate = rate }
            }
        } catch {
            DiagnosticLog.failure("playback_speed", stage: "apply", error: error)
            throw error
        }
    }
    private var finishObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    var duration: TimeInterval {
        let value = player.currentItem?.duration.seconds ?? 0
        return value.isFinite ? max(0, value) : 0
    }
    var currentTime: TimeInterval {
        get { let value = player.currentTime().seconds; return value.isFinite ? value : 0 }
        set { player.seek(to: CMTime(seconds: max(0, newValue), preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) }
    }
    var isPlaying: Bool { player.rate != 0 }
    func load(url: URL) throws {
        if url.isFileURL {
            let file = try FileHandle(forReadingFrom: url)
            try file.close()
            guard AVURLAsset(url: url).isPlayable else {
                DiagnosticLog.event("playback", stage: "unsupported_media")
                throw URLError(.cannotDecodeContentData)
            }
        }
        if let finishObserver { NotificationCenter.default.removeObserver(finishObserver) }
        let item = AVPlayerItem(url: url)
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed {
                DiagnosticLog.event("playback", stage: "load_failed")
                DispatchQueue.main.async { self?.onFinish?(false) }
            }
        }
        finishObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in self?.onFinish?(true) }
        player.replaceCurrentItem(with: item)
        speedSelection = PlaybackSpeedSelection()
    }
    func play() {
        guard player.currentItem != nil, player.currentItem?.status != .failed else {
            DiagnosticLog.event("playback", stage: "start_unavailable")
            return
        }
        speedSelection.start { player.rate = $0 }
    }
    func pause() { player.pause() }
    func stop() { player.pause(); currentTime = 0 }
    deinit { if let finishObserver { NotificationCenter.default.removeObserver(finishObserver) } }
}
