import Cocoa

/// The main workspace OSD — displays non-empty workspaces as a compact pill bar
/// or an expanded grid with drag-to-reorder support.
public class WorkspaceWindow: NSPanel {
    /// Display mode for the window.
    public enum Mode { case compact, expanded }

    /// Ordered workspace names currently displayed.
    public var workspaces: [String] = []
    /// Name of the currently focused workspace.
    public var currentWorkspace: String?
    /// Whether the window is in compact or expanded mode.
    public var mode: Mode = .compact

    /// Called when the user selects a workspace (click/tap).
    public var onSelectWorkspace: ((String) -> Void)?
    /// Called when the user reorders workspaces via drag.
    public var onOrderChanged: (([String]) -> Void)?
    /// Called when the window collapses from expanded back to compact.
    public var onCollapse: (() -> Void)?

    private var itemViews: [WorkspaceItemView] = []
    private var backgroundView: NSView
    private var closeButton: NSButton?
    private var hideTimer: Timer?
    private var draggingView: WorkspaceItemView?
    private var clickOutsideMonitor: Any?

    // Compact layout constants
    private let compactHeight: CGFloat = 28
    private let compactPadding: CGFloat = 10
    private let compactSpacing: CGFloat = 4

    // Expanded layout constants
    private let expandedItemSize: CGFloat = 100
    private let expandedSpacing: CGFloat = 12
    private let expandedPadding: CGFloat = 20
    private let expandedHeaderHeight: CGFloat = 28

    public init() {
        backgroundView = NSView(frame: .zero)

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    deinit {
        hideTimer?.invalidate()
        removeClickOutsideMonitor()
    }

    public override var canBecomeKey: Bool { mode == .expanded }
    public override var canBecomeMain: Bool { false }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 && mode == .expanded { // Escape
            fadeOut()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Show / Hide

    /// Shows the window in compact pill-bar mode.
    /// - Parameters:
    ///   - workspaces: Ordered workspace names.
    ///   - current: The currently focused workspace name.
    ///   - autoHide: Whether the window auto-hides after 1.5 seconds.
    public func show(workspaces: [String], current: String?, autoHide: Bool = true) {
        self.workspaces = workspaces
        self.currentWorkspace = current
        self.mode = .compact

        rebuildViews()
        layoutCompact(animated: false)
        orderFrontRegardless()

        hideTimer?.invalidate()
        if autoHide {
            hideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                self?.fadeOut()
            }
        }
    }

    /// Shows the window directly in expanded grid mode.
    /// - Parameters:
    ///   - workspaces: Ordered workspace names.
    ///   - current: The currently focused workspace name.
    public func showExpanded(workspaces: [String], current: String?) {
        self.workspaces = workspaces
        self.currentWorkspace = current
        self.mode = .expanded

        ignoresMouseEvents = false
        level = .popUpMenu

        rebuildViews()

        for item in itemViews {
            item.isExpanded = true
            item.updateAppearance()
        }

        layoutExpanded(animated: false)

        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 1
        }

        installClickOutsideMonitor()
    }

    /// Transitions from compact to expanded mode (animated).
    public func expand() {
        hideTimer?.invalidate()
        mode = .expanded

        ignoresMouseEvents = false
        level = .popUpMenu

        for item in itemViews {
            item.isExpanded = true
            item.updateAppearance()
        }

        layoutExpanded(animated: true)
        makeKey()
        installClickOutsideMonitor()
    }

    /// Transitions from expanded back to compact mode (animated).
    public func collapse() {
        removeClickOutsideMonitor()
        mode = .compact

        ignoresMouseEvents = true
        level = .floating

        for item in itemViews {
            item.isExpanded = false
            item.updateAppearance()
        }

        layoutCompact(animated: true)
        onCollapse?()
    }

    /// Fades the window out and resets to compact state.
    public func fadeOut() {
        removeClickOutsideMonitor()

        ignoresMouseEvents = true
        level = .floating

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1
            self.mode = .compact
            for item in self.itemViews {
                item.isExpanded = false
            }
        })
    }

    // MARK: - Click Outside Monitor

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.mode == .expanded else { return }
            let screenLoc = NSEvent.mouseLocation
            if !self.frame.contains(screenLoc) {
                self.fadeOut()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - View Hierarchy

    private func rebuildViews() {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        closeButton?.removeFromSuperview()
        closeButton = nil
        backgroundView.removeFromSuperview()

        // Create background
        backgroundView = NSView(frame: .zero)
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = Style.bgColor.cgColor
        backgroundView.layer?.cornerRadius = 8
        backgroundView.layer?.borderColor = NSColor(white: 0.25, alpha: 1).cgColor
        backgroundView.layer?.borderWidth = 1

        contentView = backgroundView

        // Create close button (hidden initially, shown in expanded mode)
        let btn = NSButton(frame: NSRect(x: 8, y: 0, width: 16, height: 16))
        btn.bezelStyle = .circular
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor(red: 1, green: 0.3, blue: 0.3, alpha: 1).cgColor
        btn.layer?.cornerRadius = 8
        btn.title = ""
        btn.target = self
        btn.action = #selector(closeButtonClicked)
        btn.isHidden = true
        backgroundView.addSubview(btn)
        closeButton = btn

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

    // MARK: - Layout

    private func layoutCompact(animated: Bool) {
        guard let screen = NSScreen.main else {
            fputs("WorkspaceWindow: no main screen available for layout\n", stderr)
            return
        }
        let visibleFrame = screen.visibleFrame

        closeButton?.isHidden = true

        // Calculate pill widths
        var totalWidth: CGFloat = 16
        let pillWidths: [CGFloat] = workspaces.map { ws in
            let textWidth = (ws as NSString).size(withAttributes: [.font: Style.font]).width
            let width = textWidth + compactPadding * 2
            totalWidth += width + compactSpacing
            return width
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
                guard i < pillWidths.count else { break }
                item.animator().frame = NSRect(x: xPos, y: yPos, width: pillWidths[i], height: compactHeight)
                xPos += pillWidths[i] + compactSpacing
            }
        }
    }

    private func layoutExpanded(animated: Bool) {
        guard let screen = NSScreen.main, !workspaces.isEmpty else {
            fputs("WorkspaceWindow: cannot layout expanded — no screen or empty workspaces\n", stderr)
            return
        }
        let visibleFrame = screen.visibleFrame

        let cols = min(workspaces.count, 5)
        let rows = (workspaces.count + cols - 1) / cols

        let windowWidth = CGFloat(cols) * (expandedItemSize + expandedSpacing) - expandedSpacing + expandedPadding * 2
        let windowHeight = CGFloat(rows) * (expandedItemSize + expandedSpacing) - expandedSpacing + expandedPadding * 2 + expandedHeaderHeight

        let windowX = visibleFrame.midX - windowWidth / 2
        let windowY = visibleFrame.midY - windowHeight / 2

        let duration = animated ? 0.25 : 0.0

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true

            self.animator().setFrame(NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight), display: true)
            self.backgroundView.animator().frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

            let closeButtonMargin: CGFloat = 12
            self.closeButton?.frame = NSRect(x: closeButtonMargin, y: windowHeight - closeButtonMargin - 14, width: 14, height: 14)
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

        let x = expandedPadding + CGFloat(col) * (expandedItemSize + expandedSpacing)
        let y = windowHeight - expandedPadding - headerHeight - CGFloat(row + 1) * (expandedItemSize + expandedSpacing) + expandedSpacing

        return NSRect(x: x, y: y, width: expandedItemSize, height: expandedItemSize)
    }

    private func indexForPoint(_ point: NSPoint) -> Int {
        let cols = min(workspaces.count, 5)
        let windowHeight = backgroundView.bounds.height

        let col = Int((point.x - expandedPadding) / (expandedItemSize + expandedSpacing))
        let row = Int((windowHeight - expandedPadding - expandedHeaderHeight - point.y) / (expandedItemSize + expandedSpacing))

        let clampedCol = max(0, min(col, cols - 1))
        let clampedRow = max(0, row)

        let index = clampedRow * cols + clampedCol
        return max(0, min(index, workspaces.count - 1))
    }

    // MARK: - Drag Reorder

    private func handleDragMove(to point: NSPoint) {
        guard mode == .expanded, let dragging = draggingView else { return }

        let targetIndex = indexForPoint(point)
        let currentIndex = dragging.index

        guard targetIndex != currentIndex,
              targetIndex < workspaces.count,
              currentIndex < workspaces.count else { return }

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

    private func handleDragEnd() {
        guard let dragging = draggingView else { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            dragging.animator().frame = expandedFrameForIndex(dragging.index, windowHeight: backgroundView.bounds.height, headerHeight: expandedHeaderHeight)
        }

        draggingView = nil
    }
}
