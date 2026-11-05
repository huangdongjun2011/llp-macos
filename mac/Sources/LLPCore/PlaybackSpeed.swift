import Foundation

public enum PlaybackSpeed: Float, CaseIterable {
    case half = 0.5
    case normal = 1
    case double = 2

    public var title: String {
        switch self {
        case .half: return "0.5X"
        case .normal: return "1X"
        case .double: return "2X"
        }
    }
}

/// Commits the displayed selection only after the playback engine accepts it.
public struct PlaybackSpeedSelection {
    public private(set) var speed: PlaybackSpeed = .normal

    public init() {}

    public mutating func select(_ speed: PlaybackSpeed, apply: (Float) throws -> Void) rethrows {
        try apply(speed.rawValue)
        self.speed = speed
    }

    public mutating func start(apply: (Float) -> Void) {
        select(.normal, apply: apply)
    }
}
