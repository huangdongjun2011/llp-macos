import AppKit
import LLPCore

final class SegmentProgressView: NSControl {
    var duration: TimeInterval = 0 {
        didSet {
            duration = max(duration, 0)
            needsDisplay = true
        }
    }

    var currentTime: TimeInterval = 0 {
        didSet {
            currentTime = clamped(currentTime)
            needsDisplay = true
        }
    }

    var startMarker: TimeInterval? {
        didSet {
            startMarker = startMarker.map(clamped)
            needsDisplay = true
        }
    }

    var endMarker: TimeInterval? {
        didSet {
            endMarker = endMarker.map(clamped)
            needsDisplay = true
        }
    }

    var isReplayingSegment = false {
        didSet { needsDisplay = true }
    }

    var onSeek: ((TimeInterval) -> Void)?
    var onMarkerChange: ((MarkerUpdate) -> Void)?

    private enum DragTarget {
        case start
        case end
        case playhead
    }

    private var dragTarget: DragTarget?
    private let trackHeight: CGFloat = 10
    private let markerGap: CGFloat = 4
    private let handleSize = NSSize(width: 13, height: 18)
    private let horizontalInset: CGFloat = 7

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 44)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let track = trackRect()
        let radius = trackHeight / 2
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard duration > 0 else {
            drawHandle(at: track.minX, color: .systemGreen, pointsUp: true)
            drawHandle(at: track.maxX, color: .systemRed, pointsUp: false)
            return
        }

        let startX = xPosition(for: startMarker ?? 0)
        let endX = xPosition(for: endMarker ?? duration)
        let currentX = xPosition(for: currentTime)

        drawRange(from: startX, to: endX, color: NSColor.systemBlue.withAlphaComponent(0.2), in: track)

        if isReplayingSegment {
            drawRange(from: startX, to: min(max(currentX, startX), endX), color: .systemBlue, in: track)
        } else {
            drawRange(from: track.minX, to: currentX, color: .secondaryLabelColor, in: track)
        }

        drawPlayhead(at: currentX, in: track)
        drawHandle(at: startX, color: .systemGreen, pointsUp: true)
        drawHandle(at: endX, color: .systemRed, pointsUp: false)
    }

    override func mouseDown(with event: NSEvent) {
        guard duration > 0 else { return }

        let point = convert(event.locationInWindow, from: nil)
        dragTarget = nearestTarget(to: point)
        applyDrag(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard duration > 0 else { return }

        let point = convert(event.locationInWindow, from: nil)
        applyDrag(at: point)
    }

    override func mouseUp(with event: NSEvent) {
        guard duration > 0 else {
            dragTarget = nil
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        applyDrag(at: point)
        dragTarget = nil
    }

    private func applyDrag(at point: NSPoint) {
        let time = time(forX: point.x)

        switch dragTarget {
        case .start:
            onMarkerChange?(.setStart(time))
        case .end:
            onMarkerChange?(.setEnd(time))
        case .playhead, nil:
            onSeek?(time)
        }
    }

    private func nearestTarget(to point: NSPoint) -> DragTarget {
        // Keep marker hit areas in their own vertical lanes so track clicks seek,
        // including when the two markers share the same time.
        if handleRect(at: xPosition(for: startMarker ?? 0), pointsUp: true).insetBy(dx: -5, dy: 0).contains(point) {
            return .start
        }
        if handleRect(at: xPosition(for: endMarker ?? duration), pointsUp: false).insetBy(dx: -5, dy: 0).contains(point) {
            return .end
        }

        return .playhead
    }

    private func drawRange(from startX: CGFloat, to endX: CGFloat, color: NSColor, in track: NSRect) {
        guard endX > startX else { return }

        let rect = NSRect(x: startX, y: track.minY, width: endX - startX, height: track.height)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()
    }

    func handleRect(at x: CGFloat, pointsUp: Bool) -> NSRect {
        let track = trackRect()
        let height = handleSize.height / 2
        return NSRect(
            x: x - handleSize.width / 2,
            y: pointsUp ? track.minY - markerGap - height : track.maxY + markerGap,
            width: handleSize.width,
            height: height
        )
    }

    func handlePath(at x: CGFloat, pointsUp: Bool) -> NSBezierPath {
        let rect = handleRect(at: x, pointsUp: pointsUp)
        let path = NSBezierPath()
        // AppKit coordinates increase upward: start points up, end points down.
        path.move(to: NSPoint(x: x, y: pointsUp ? rect.maxY : rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: pointsUp ? rect.minY : rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: pointsUp ? rect.minY : rect.maxY))
        path.close()
        return path
    }

    private func drawHandle(at x: CGFloat, color: NSColor, pointsUp: Bool) {
        color.setFill()
        handlePath(at: x, pointsUp: pointsUp).fill()
    }

    private func drawPlayhead(at x: CGFloat, in track: NSRect) {
        NSColor.labelColor.setFill()
        let rect = NSRect(x: x - 1, y: track.minY - 7, width: 2, height: track.height + 14)
        NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
    }

    func trackRect() -> NSRect {
        NSRect(
            x: horizontalInset,
            y: bounds.midY - trackHeight / 2,
            width: max(bounds.width - horizontalInset * 2, 1),
            height: trackHeight
        )
    }

    private func xPosition(for time: TimeInterval) -> CGFloat {
        let track = trackRect()
        guard duration > 0 else { return track.minX }

        return track.minX + track.width * CGFloat(clamped(time) / duration)
    }

    private func time(forX x: CGFloat) -> TimeInterval {
        let track = trackRect()
        guard duration > 0, track.width > 0 else { return 0 }

        let ratio = min(max((x - track.minX) / track.width, 0), 1)
        return TimeInterval(ratio) * duration
    }

    private func clamped(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), duration)
    }
}
