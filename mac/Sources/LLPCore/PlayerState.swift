import Foundation

public enum MarkerUpdate: Equatable {
    case setStart(TimeInterval)
    case setEnd(TimeInterval)
}

public struct PlayerState: Equatable {
    public private(set) var duration: TimeInterval
    public private(set) var startMarker: TimeInterval?
    public private(set) var endMarker: TimeInterval?
    public private(set) var isReplayingSegment: Bool

    public init(
        duration: TimeInterval = 0,
        startMarker: TimeInterval? = nil,
        endMarker: TimeInterval? = nil,
        isReplayingSegment: Bool = false
    ) {
        self.duration = max(duration, 0)
        self.startMarker = startMarker
        self.endMarker = endMarker
        self.isReplayingSegment = isReplayingSegment
        normalizeMarkers()
    }

    public var segment: LoopSegment? {
        LoopSegment(
            start: startMarker ?? 0,
            end: endMarker ?? duration,
            duration: duration
        )
    }

    public mutating func loadTrack(duration: TimeInterval) {
        self.duration = max(duration, 0)
        startMarker = nil
        endMarker = nil
        isReplayingSegment = false
    }

    public mutating func apply(_ update: MarkerUpdate) {
        switch update {
        case .setStart(let value):
            startMarker = clamped(value)
            if let endMarker, let startMarker, startMarker >= endMarker {
                self.endMarker = nil
            }
        case .setEnd(let value):
            endMarker = clamped(value)
            if let startMarker, let endMarker, endMarker <= startMarker {
                self.startMarker = nil
            }
        }
        isReplayingSegment = false
    }

    @discardableResult
    public mutating func moveSelectedSegmentForward() -> Bool {
        moveSelectedSegment(direction: 1)
    }

    @discardableResult
    public mutating func moveSelectedSegmentBackward() -> Bool {
        moveSelectedSegment(direction: -1)
    }

    public mutating func beginSegmentReplay() {
        guard segment != nil else { return }
        isReplayingSegment = true
    }

    public mutating func endSegmentReplay() {
        isReplayingSegment = false
    }

    private mutating func normalizeMarkers() {
        startMarker = startMarker.map(clamped)
        endMarker = endMarker.map(clamped)

        if let startMarker, let endMarker, startMarker >= endMarker {
            self.startMarker = nil
            self.endMarker = nil
        }

        if duration == 0 {
            startMarker = nil
            endMarker = nil
            isReplayingSegment = false
        }
    }

    private func clamped(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), duration)
    }

    private mutating func moveSelectedSegment(direction: Double) -> Bool {
        guard
            duration > 0,
            let startMarker,
            let endMarker,
            startMarker < endMarker
        else {
            return false
        }

        let segmentLength = endMarker - startMarker
        guard segmentLength > 0, segmentLength <= duration else { return false }

        let maximumStart = duration - segmentLength
        let proposedStart = startMarker + segmentLength * direction
        let newStart = min(max(proposedStart, 0), maximumStart)
        let newEnd = newStart + segmentLength

        guard newStart != startMarker || newEnd != endMarker else { return false }

        self.startMarker = newStart
        self.endMarker = newEnd
        isReplayingSegment = false
        return true
    }
}
