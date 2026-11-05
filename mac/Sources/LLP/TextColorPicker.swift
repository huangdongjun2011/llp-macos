import AppKit

/// Three favorite text colors with a deliberately limited replacement palette.
final class TextColorPicker: NSStackView, NSPopoverDelegate {
    static let palette: [(name: String, color: NSColor)] = [
        ("Red", .red), ("Black", .black), ("Green", .green),
        ("Blue", .blue), ("Orange", .orange), ("Yellow", .yellow),
        ("Purple", .purple), ("Brown", .brown), ("Gray", .gray),
        ("White", .white), ("Cyan", .cyan), ("Magenta", .magenta)
    ]

    private(set) var colorIndices = [0, 1, 2]
    private(set) var selectedIndex = 1
    private(set) var circles: [ColorCircleButton] = []
    private(set) var paletteButtons: [ColorCircleButton] = []
    private(set) var editingIndex: Int?
    let popover = NSPopover()
    var onColorSelected: ((NSColor) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        spacing = 8
        for index in 0..<3 {
            let button = ColorCircleButton()
            button.tag = index
            button.target = self
            button.action = #selector(selectCircle(_:))
            button.onDoubleClick = { [weak self] in self?.showPalette(for: index) }
            circles.append(button)
            addArrangedSubview(button)
        }
        refresh()
        popover.behavior = .transient
        popover.delegate = self
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.spacing = 8
        for row in 0..<3 {
            let stack = NSStackView()
            stack.spacing = 8
            for index in (row * 4)..<(row * 4 + 4) {
                let button = ColorCircleButton()
                button.color = Self.palette[index].color
                button.setAccessibilityLabel(Self.palette[index].name)
                button.toolTip = Self.palette[index].name
                button.tag = index
                button.target = self
                button.action = #selector(replaceColor(_:))
                paletteButtons.append(button)
                stack.addArrangedSubview(button)
            }
            grid.addArrangedSubview(stack)
        }
        grid.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        let controller = NSViewController()
        controller.view = grid
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 176, height: 136)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func selectCircle(_ sender: NSButton) {
        selectedIndex = sender.tag
        refresh()
        onColorSelected?(Self.palette[colorIndices[selectedIndex]].color)
    }

    func showPalette(for index: Int) {
        guard circles.indices.contains(index) else { return }
        editingIndex = index
        selectCircle(circles[index])
        for button in paletteButtons {
            button.state = button.tag == colorIndices[index] ? .on : .off
        }
        if circles[index].window != nil {
            popover.show(relativeTo: circles[index].bounds, of: circles[index], preferredEdge: .maxY)
        }
    }

    @objc private func replaceColor(_ sender: NSButton) {
        guard let index = editingIndex, Self.palette.indices.contains(sender.tag) else { return }
        colorIndices[index] = sender.tag
        selectedIndex = index
        editingIndex = nil
        popover.close()
        refresh()
        onColorSelected?(Self.palette[sender.tag].color)
    }

    func popoverDidClose(_ notification: Notification) {
        editingIndex = nil
    }

    private func refresh() {
        for (index, button) in circles.enumerated() {
            let entry = Self.palette[colorIndices[index]]
            button.color = entry.color
            button.state = index == selectedIndex ? .on : .off
            button.setAccessibilityLabel("Text color \(index + 1): \(entry.name)")
            button.toolTip = "\(entry.name): click to use; double-click to change (Option-Space with keyboard)"
        }
    }
}

final class ColorCircleButton: NSButton {
    var color: NSColor = .black { didSet { needsDisplay = true } }
    var onDoubleClick: (() -> Void)?
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setButtonType(.pushOnPushOff)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let onDoubleClick {
            onDoubleClick()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " ", event.modifierFlags.contains(.option), let onDoubleClick {
            onDoubleClick()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        color.setFill()
        circle.fill()
        NSColor.secondaryLabelColor.setStroke()
        circle.lineWidth = 1
        circle.stroke()
        if state == .on {
            let rgb = color.usingColorSpace(.sRGB) ?? .black
            let brightness = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
            (brightness > 0.55 ? NSColor.black : NSColor.white).setStroke()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: 9, y: 16))
            check.line(to: NSPoint(x: 14, y: isFlipped ? 21 : 11))
            check.line(to: NSPoint(x: 23, y: isFlipped ? 11 : 21))
            check.lineWidth = 2.5
            check.stroke()
        }
    }
}
