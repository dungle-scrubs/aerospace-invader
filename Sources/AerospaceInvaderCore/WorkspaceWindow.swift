import Cocoa

public class WorkspaceWindow: NSPanel {
    public enum Mode { case compact, expanded }

    public var workspaces: [String] = []
    public var currentWorkspace: String?
    public var mode: Mode = .compact

    public var onSelectWorkspace: ((String) -> Void)?
    public var onOrderChanged: (([String]) -> Void)?
    public var onCollapse: (() -> Void)?

    private var itemViews: [WorkspaceItemView] = []
    private var backgroundView: NSView!
    private var closeButton: NSButton?
    private var hideTimer: Timer?
    private var draggingView: WorkspaceItemView?
    private var clickOutsideMonitor: Any?

    // Compact layout constants
    private let compactHeight: CGFloat = 28
    private let compactPadding: CGFloat = 10
    private let compactSpacing: CGFloat = 4

    // Expanded layout constants
    private let expandedItemWidth: CGFloat = 80
    private let expandedItemHeight: CGFloat = 50
    private let expandedSpacing: CGFloat = 10
    private let expandedPadding: CGFloat = 16
    private let expandedHeaderHeight: CGFloat = 24

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = false
    }

    public override var canBecomeKey: Bool { true }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 && mode == .expanded { // Escape
            fadeOut()
        } else {
            super.keyDown(with: event)
        }
    }

    public func show(workspaces: [String], current: String?, autoHide: Bool = true) {
        self.workspaces = workspaces
        self.currentWorkspace = current
        self.mode = .compact

        rebuildViews()
        layoutCompact(animated: false)
        makeKeyAndOrderFront(nil)

        hideTimer?.invalidate()
        if autoHide {
            hideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                self?.fadeOut()
            }
        }
    }

    public func expand() {
        hideTimer?.invalidate()
        mode = .expanded

        for item in itemViews {
            item.isExpanded = true
            item.updateAppearance()
        }

        layoutExpanded(animated: true)

        // Make key so we can receive keyboard events
        makeKey()

        // Monitor for click outside
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.mode == .expanded else { return }
            let screenLoc = NSEvent.mouseLocation
            if !self.frame.contains(screenLoc) {
                self.fadeOut()
            }
        }
    }

    public func collapse() {
        removeClickOutsideMonitor()
        mode = .compact

        for item in itemViews {
            item.isExpanded = false
            item.updateAppearance()
        }

        layoutCompact(animated: true)
        onCollapse?()
    }

    public func fadeOut() {
        removeClickOutsideMonitor()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1
            self.mode = .compact
            // Reset item views for next show
            for item in self.itemViews {
                item.isExpanded = false
            }
        })
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    private func rebuildViews() {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        closeButton?.removeFromSuperview()
        closeButton = nil
        backgroundView?.removeFromSuperview()

        // Create background
        backgroundView = NSView(frame: .zero)
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = Style.bgColor.cgColor
        backgroundView.layer?.cornerRadius = 8
        backgroundView.layer?.borderColor = NSColor(white: 0.25, alpha: 1).cgColor
        backgroundView.layer?.borderWidth = 1

        contentView = backgroundView

        // Create close button (hidden initially, shown in expanded mode)
        closeButton = NSButton(frame: NSRect(x: 8, y: 0, width: 16, height: 16))
        closeButton?.bezelStyle = .circular
        closeButton?.isBordered = false
        closeButton?.wantsLayer = true
        closeButton?.layer?.backgroundColor = NSColor(red: 1, green: 0.3, blue: 0.3, alpha: 1).cgColor
        closeButton?.layer?.cornerRadius = 8
        closeButton?.title = ""
        closeButton?.target = self
        closeButton?.action = #selector(closeButtonClicked)
        closeButton?.isHidden = true
        backgroundView.addSubview(closeButton!)

        // Create item views
        for (i, ws) in workspaces.enumerated() {
            let item = WorkspaceItemView(workspace: ws, index: i)
            item.isActive = (ws == currentWorkspace)
            item.isExpanded = (mode == .expanded)

            item.onClick = { [weak self] ws in
                self?.onSelectWorkspace?(ws)
            }
            item.onDragStart = { [weak self, weak item] in
                self?.draggingView = item
            }
            item.onDragMove = { [weak self] pt in
                self?.handleDragMove(to: pt)
            }
            item.onDragEnd = { [weak self] in
                self?.handleDragEnd()
            }

            backgroundView.addSubview(item)
            itemViews.append(item)
        }
    }

    @objc private func closeButtonClicked() {
        fadeOut()
    }

    private func layoutCompact(animated: Bool) {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        // Hide close button in compact mode
        closeButton?.isHidden = true

        // Calculate pill widths
        var totalWidth: CGFloat = 16
        var pillWidths: [CGFloat] = []

        for ws in workspaces {
            let textWidth = (ws as NSString).size(withAttributes: [.font: Style.font]).width
            let width = textWidth + compactPadding * 2
            pillWidths.append(width)
            totalWidth += width + compactSpacing
        }
        totalWidth += 8

        let windowHeight: CGFloat = compactHeight + 16
        let windowX = visibleFrame.midX - totalWidth / 2
        let windowY = visibleFrame.maxY - windowHeight - 8

        let duration = animated ? 0.25 : 0.0

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true

            self.animator().setFrame(NSRect(x: windowX, y: windowY, width: totalWidth, height: windowHeight), display: true)
            self.backgroundView.animator().frame = NSRect(x: 0, y: 0, width: totalWidth, height: windowHeight)

            var xPos: CGFloat = 8
            let yPos: CGFloat = 8

            for (i, item) in itemViews.enumerated() {
                item.animator().frame = NSRect(x: xPos, y: yPos, width: pillWidths[i], height: compactHeight)
                xPos += pillWidths[i] + compactSpacing
            }
        }
    }

    private func layoutExpanded(animated: Bool) {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        let cols = min(workspaces.count, 5)
        let rows = (workspaces.count + cols - 1) / cols

        // Add extra space at top for close button
        let windowWidth = CGFloat(cols) * (expandedItemWidth + expandedSpacing) - expandedSpacing + expandedPadding * 2
        let windowHeight = CGFloat(rows) * (expandedItemHeight + expandedSpacing) - expandedSpacing + expandedPadding * 2 + expandedHeaderHeight

        let windowX = visibleFrame.midX - windowWidth / 2
        let windowY = visibleFrame.maxY - windowHeight - 50

        let duration = animated ? 0.25 : 0.0

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true

            self.animator().setFrame(NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight), display: true)
            self.backgroundView.animator().frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

            // Position close button in upper left
            self.closeButton?.frame = NSRect(x: 10, y: windowHeight - 20, width: 14, height: 14)
            self.closeButton?.isHidden = false

            for item in itemViews {
                item.animator().frame = expandedFrameForIndex(item.index, windowHeight: windowHeight, headerHeight: expandedHeaderHeight)
            }
        }
    }

    private func expandedFrameForIndex(_ index: Int, windowHeight: CGFloat, headerHeight: CGFloat = 0) -> NSRect {
        let cols = min(workspaces.count, 5)
        let col = index % cols
        let row = index / cols

        let x = expandedPadding + CGFloat(col) * (expandedItemWidth + expandedSpacing)
        let y = windowHeight - expandedPadding - headerHeight - CGFloat(row + 1) * (expandedItemHeight + expandedSpacing) + expandedSpacing

        return NSRect(x: x, y: y, width: expandedItemWidth, height: expandedItemHeight)
    }

    private func indexForPoint(_ point: NSPoint) -> Int {
        let cols = min(workspaces.count, 5)
        let windowHeight = backgroundView.bounds.height

        let col = Int((point.x - expandedPadding) / (expandedItemWidth + expandedSpacing))
        let row = Int((windowHeight - expandedPadding - point.y) / (expandedItemHeight + expandedSpacing))

        let clampedCol = max(0, min(col, cols - 1))
        let clampedRow = max(0, row)

        var index = clampedRow * cols + clampedCol
        index = max(0, min(index, workspaces.count - 1))
        return index
    }

    private func handleDragMove(to point: NSPoint) {
        guard mode == .expanded, let dragging = draggingView else { return }

        let targetIndex = indexForPoint(point)
        let currentIndex = dragging.index

        if targetIndex != currentIndex {
            let item = workspaces.remove(at: currentIndex)
            workspaces.insert(item, at: targetIndex)

            for (i, ws) in workspaces.enumerated() {
                if let view = itemViews.first(where: { $0.workspace == ws }) {
                    view.index = i
                }
            }

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                for view in itemViews where view !== dragging {
                    view.animator().frame = expandedFrameForIndex(view.index, windowHeight: backgroundView.bounds.height, headerHeight: expandedHeaderHeight)
                }
            }

            onOrderChanged?(workspaces)
        }
    }

    private func handleDragEnd() {
        guard let dragging = draggingView else { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            dragging.animator().frame = expandedFrameForIndex(dragging.index, windowHeight: backgroundView.bounds.height, headerHeight: expandedHeaderHeight)
        }

        draggingView = nil
    }
}
