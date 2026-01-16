import Cocoa

public class WorkspaceItemView: NSView {
    public let workspace: String
    public var index: Int
    public var isActive: Bool = false {
        didSet { updateAppearance() }
    }
    public var isExpanded: Bool = false

    public var onClick: ((String) -> Void)?
    public var onDragStart: (() -> Void)?
    public var onDragMove: ((NSPoint) -> Void)?
    public var onDragEnd: (() -> Void)?

    private var label: NSTextField!
    private var isDragging = false
    private var dragOffset: NSPoint = .zero
    private var mouseDownLocation: NSPoint = .zero

    public init(workspace: String, index: Int) {
        self.workspace = workspace
        self.index = index
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 4

        label = NSTextField(labelWithString: workspace)
        label.font = Style.font
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
    }

    public func updateAppearance() {
        if isExpanded {
            // Expanded tile style
            layer?.cornerRadius = 10
            if isActive {
                layer?.backgroundColor = NSColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1).cgColor
                layer?.borderColor = Style.activeColor.cgColor
                layer?.borderWidth = 2
            } else {
                layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
                layer?.borderWidth = 0
            }
            label.textColor = .white
            label.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold)
        } else {
            // Compact pill style
            layer?.cornerRadius = 4
            if isActive {
                layer?.backgroundColor = NSColor(red: 0, green: 1, blue: 0, alpha: 0.15).cgColor
                layer?.borderColor = Style.borderColor.cgColor
                layer?.borderWidth = 1
                label.textColor = Style.activeColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = 0
                label.textColor = Style.inactiveColor
            }
            label.font = Style.font
        }
    }

    public override func mouseDown(with event: NSEvent) {
        if isExpanded {
            isDragging = true
            let loc = convert(event.locationInWindow, from: nil)
            dragOffset = NSPoint(x: loc.x, y: loc.y)
            mouseDownLocation = superview?.convert(event.locationInWindow, from: nil) ?? .zero
            superview?.addSubview(self)
            onDragStart?()

            NSCursor.closedHand.push()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                self.animator().alphaValue = 0.85
                self.layer?.shadowColor = NSColor.black.cgColor
                self.layer?.shadowOpacity = 0.5
                self.layer?.shadowRadius = 12
            }
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isDragging, isExpanded, let sv = superview else { return }
        let loc = sv.convert(event.locationInWindow, from: nil)
        frame.origin = NSPoint(x: loc.x - dragOffset.x, y: loc.y - dragOffset.y)
        onDragMove?(NSPoint(x: frame.midX, y: frame.midY))
    }

    public override func mouseUp(with event: NSEvent) {
        if isExpanded && isDragging {
            let mouseUpLocation = superview?.convert(event.locationInWindow, from: nil) ?? .zero
            let distance = hypot(mouseUpLocation.x - mouseDownLocation.x, mouseUpLocation.y - mouseDownLocation.y)

            isDragging = false
            NSCursor.pop()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                self.animator().alphaValue = 1
                self.layer?.shadowOpacity = 0
            }

            if distance < 5 {
                onClick?(workspace)
            } else {
                onDragEnd?()
            }
        } else {
            onClick?(workspace)
        }
    }

    public override var mouseDownCanMoveWindow: Bool { false }
}
