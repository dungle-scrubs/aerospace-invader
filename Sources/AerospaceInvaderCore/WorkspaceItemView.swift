import Cocoa

/// A single workspace item rendered as a compact pill or expanded tile.
/// Handles click and drag interactions; delegates actions via closures.
public class WorkspaceItemView: NSView {
    /// The workspace name this view represents.
    public let workspace: String

    /// Current position index within the parent's ordered list (mutated during drag reorder).
    public var index: Int

    /// Whether this workspace is the currently focused one.
    public var isActive: Bool = false {
        didSet { updateAppearance() }
    }

    /// Whether the view is rendered in expanded tile mode vs compact pill mode.
    public var isExpanded: Bool = false

    /// Called when the user clicks (or taps-without-dragging) this workspace.
    public var onClick: ((String) -> Void)?
    /// Called when a drag gesture begins.
    public var onDragStart: (() -> Void)?
    /// Called continuously as the view is dragged, with the midpoint in superview coords.
    public var onDragMove: ((NSPoint) -> Void)?
    /// Called when the drag gesture ends.
    public var onDragEnd: (() -> Void)?

    private lazy var label: NSTextField = {
        let lbl = NSTextField(labelWithString: workspace)
        lbl.font = Style.font
        lbl.alignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private var isDragging = false
    private var dragOffset: NSPoint = .zero
    private var mouseDownLocation: NSPoint = .zero

    /// Creates a workspace item view.
    /// - Parameters:
    ///   - workspace: The workspace name to display.
    ///   - index: The initial position index.
    public init(workspace: String, index: Int) {
        self.workspace = workspace
        self.index = index
        super.init(frame: .zero)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkspaceItemView is programmatic-only") }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 4

        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    /// Updates colors, corner radius, and font based on `isActive` and `isExpanded` state.
    public func updateAppearance() {
        if isExpanded {
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

    // MARK: - Mouse Events

    public override func mouseDown(with event: NSEvent) {
        guard isExpanded else { return }

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

    public override func mouseDragged(with event: NSEvent) {
        guard isDragging, isExpanded, let sv = superview else { return }
        let loc = sv.convert(event.locationInWindow, from: nil)
        frame.origin = NSPoint(x: loc.x - dragOffset.x, y: loc.y - dragOffset.y)
        onDragMove?(NSPoint(x: frame.midX, y: frame.midY))
    }

    public override func mouseUp(with event: NSEvent) {
        if isDragging {
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
