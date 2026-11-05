import Foundation

public struct LoopSegment: Equatable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init?(start: TimeInterval, end: TimeInterval, duration: TimeInterval) {
        guard duration.isFinite, duration > 0 else { return nil }
        guard start.isFinite, end.isFinite else { return nil }

        let clampedStart = min(max(start, 0), duration)
        let clampedEnd = min(max(end, 0), duration)

        guard clampedEnd > clampedStart else { return nil }

        self.start = clampedStart
        self.end = clampedEnd
    }

    public func shouldRestart(at currentTime: TimeInterval) -> Bool {
        currentTime >= end
    }
}
