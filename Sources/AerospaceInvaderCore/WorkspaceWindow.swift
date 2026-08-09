import Carbon.HIToolbox
import Cocoa

/// The main workspace OSD — displays non-empty workspaces as a compact pill bar
/// or an expanded grid with drag-to-reorder support.
public final class WorkspaceWindow: NSPanel {
    /// Display mode for the window.
    public enum Mode { case compact, expanded }

    /// Deep display module that owns ordering, focus, mode, and every frame. The window
    /// is a thin adapter that renders the display's state and forwards intents back into it.
    public let display: WorkspaceDisplay

    /// Ordered workspace names currently displayed. Proxies to `display.state`.
    public var workspaces: [String] {
        get { display.state.workspaces }
        set { display.update(workspaces: newValue, focused: display.state.focused) }
    }
    /// Name of the currently focused workspace. Proxies to `display.state`.
    public var currentWorkspace: String? {
        get { display.state.focused }
        set { display.update(workspaces: display.state.workspaces, focused: newValue) }
    }
    /// Whether the window is in compact or expanded mode. Proxies to `display.state`.
    public var mode: Mode {
        get { display.state.mode }
        set {
            if newValue == .expanded { display.expand() } else { display.collapse() }
        }
    }

    /// Called when the user selects a workspace (click/tap).
    public var onSelectWorkspace: ((String) -> Void)?
    /// Called when the user reorders workspaces via drag.
    public var onOrderChanged: (([String]) -> Void)?
    /// Called when the window collapses from expanded back to compact.
    public var onCollapse: (() -> Void)?
    /// Called after the window finishes fading out. One-shot (non-daemon) invocations use this
    /// to terminate the process, which otherwise lingers because hiding a window never closes it.
    public var onDismiss: (() -> Void)?

    private var itemViews: [WorkspaceItemView] = []
    private var backgroundView: NSView
    private var closeButton: NSButton?
    private var clickOutsideMonitor: Any?

    /// Deep collaborators — the window is a thin compositor.
    private let autoHide: AutoHidePolicy
    private let drag: DragCoordinator
    private var draggingView: WorkspaceItemView?

    // Layout is centralized in WorkspaceDisplay.LayoutConfig + WindowLayout.
    private var compactHeight: CGFloat { display.config.compactHeight }
    private var compactSpacing: CGFloat { display.config.compactSpacing }

    /// Creates a window backed by the given display. When no display is provided a
    /// default one is created so existing call sites remain unbroken.
    /// - Parameters:
    ///   - display: The display model to render.
    ///   - autoHide: Injected hide policy (for tests). Defaults to 1.5s.
    public init(display: WorkspaceDisplay = WorkspaceDisplay(), autoHide: AutoHidePolicy = AutoHidePolicy()) {
        self.display = display
        self.autoHide = autoHide
        self.drag = DragCoordinator(display: display)
        backgroundView = NSView(frame: .zero)

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        OverlayShell.configure(self)
        level = .floating
        ignoresMouseEvents = true
    }

    deinit {
        autoHide.cancel()
        removeClickOutsideMonitor()
    }

    public override var canBecomeKey: Bool { mode == .expanded }
    public override var canBecomeMain: Bool { false }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) && mode == .expanded {
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
        display.update(workspaces: workspaces, focused: current)
        display.collapse()

        rebuildViews()
        layoutCompact(animated: false)
        orderFrontRegardless()

        self.autoHide.cancel()
        if autoHide {
            self.autoHide.schedule { [weak self] in self?.fadeOut() }
        }
    }

    /// Shows the window directly in expanded grid mode.
    /// - Parameters:
    ///   - workspaces: Ordered workspace names.
    ///   - current: The currently focused workspace name.
    public func showExpanded(workspaces: [String], current: String?) {
        display.update(workspaces: workspaces, focused: current)
        display.expand()

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
        autoHide.cancel()
        display.expand()

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
        display.collapse()

        ignoresMouseEvents = true
        level = .floating

        for item in itemViews {
            item.isExpanded = false
            item.updateAppearance()
        }

        layoutCompact(animated: true)
        onCollapse?()
    }

    /// Fades the window out and resets to compact state. Delegates animation to
    /// `OverlayShell` so both overlays share one fade path.
    public func fadeOut() {
        removeClickOutsideMonitor()
        ignoresMouseEvents = true
        level = .floating
        OverlayShell.fadeOut(self, duration: 0.2) { [weak self] in
            guard let self = self else { return }
            self.display.collapse()
            for item in self.itemViews { item.isExpanded = false }
            self.onDismiss?()
        }
    }

    // MARK: - Click Outside Monitor

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = OverlayShell.installClickOutsideMonitor(for: self) { [weak self] in
            guard let self = self, self.mode == .expanded else { return }
            self.fadeOut()
        }
    }

    private func removeClickOutsideMonitor() {
        OverlayShell.removeMonitor(clickOutsideMonitor)
        clickOutsideMonitor = nil
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
        backgroundView.layer?.backgroundColor = Style.Overlay.background.cgColor
        backgroundView.layer?.cornerRadius = Style.Overlay.cornerRadius
        backgroundView.layer?.borderColor = Style.Overlay.border.cgColor
        backgroundView.layer?.borderWidth = Style.Overlay.borderWidth

        contentView = backgroundView

        // Create close button (hidden initially, shown in expanded mode)
        let btn = NSButton(frame: NSRect(x: 8, y: 0, width: 16, height: 16))
        btn.bezelStyle = .circular
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = Style.closeButtonColor.cgColor
        btn.layer?.cornerRadius = 8
        btn.title = ""
        btn.target = self
        btn.action = #selector(closeButtonClicked)
        btn.isHidden = true
        backgroundView.addSubview(btn)
        closeButton = btn

        // Create item views — drag state owned by DragCoordinator
        for (i, ws) in workspaces.enumerated() {
            let item = WorkspaceItemView(workspace: ws, index: i)
            item.isActive = (ws == currentWorkspace)
            item.isExpanded = (mode == .expanded)

            item.onClick = { [weak self] ws in
                self?.onSelectWorkspace?(ws)
            }
            item.onDragStart = { [weak self, weak item] in
                self?.draggingView = item
                if let idx = item?.index { self?.drag.begin(at: idx) }
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

    // MARK: - Layout — delegated to WindowLayout (pure geometry)

    private func layoutCompact(animated: Bool) {
        guard let screen = NSScreen.main else {
            fputs("WorkspaceWindow: no main screen available for layout\n", stderr)
            return
        }
        let visibleFrame = screen.visibleFrame
        closeButton?.isHidden = true

        let windowFrame = WindowLayout.compactWindowFrame(display: display, in: visibleFrame)
        let contentSize = WindowLayout.compactContentSize(display: display)
        let pillFrames = WindowLayout.compactItemFrames(display: display)

        let duration = animated ? 0.25 : 0.0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(windowFrame, display: true)
            self.backgroundView.animator().frame = NSRect(
                x: 0, y: 0, width: contentSize.width, height: contentSize.height)
            for (i, item) in itemViews.enumerated() where i < pillFrames.count {
                item.animator().frame = pillFrames[i]
            }
        }
    }

    private var expandedGrid: GridLayout { display.expandedGrid }

    private func layoutExpanded(animated: Bool) {
        guard let screen = NSScreen.main, !workspaces.isEmpty else {
            fputs("WorkspaceWindow: cannot layout expanded — no screen or empty workspaces\n", stderr)
            return
        }
        let visibleFrame = screen.visibleFrame
        guard let windowFrame = WindowLayout.expandedWindowFrame(display: display, in: visibleFrame) else { return }
        let contentSize = WindowLayout.expandedContentSize(display: display)

        let duration = animated ? 0.25 : 0.0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(windowFrame, display: true)
            self.backgroundView.animator().frame = NSRect(
                x: 0, y: 0, width: contentSize.width, height: contentSize.height)
            let closeButtonMargin: CGFloat = 12
            self.closeButton?.frame = NSRect(
                x: closeButtonMargin, y: contentSize.height - closeButtonMargin - 14, width: 14, height: 14
            )
            self.closeButton?.isHidden = false
            for item in itemViews {
                item.animator().frame = WindowLayout.expandedFrame(
                    for: item.index, display: display, windowHeight: contentSize.height)
            }
        }
    }

    private func expandedFrameForIndex(_ index: Int, windowHeight: CGFloat) -> NSRect {
        WindowLayout.expandedFrame(for: index, display: display, windowHeight: windowHeight)
    }

    private func indexForPoint(_ point: NSPoint) -> Int {
        WindowLayout.expandedIndex(for: point, display: display, windowHeight: backgroundView.bounds.height)
    }

    // MARK: - Drag Reorder — delegated to DragCoordinator for state machine

    private func handleDragMove(to point: NSPoint) {
        guard mode == .expanded, let dragging = draggingView, drag.isDragging else { return }

        guard let (newOrder, _) = drag.move(to: point, windowHeight: backgroundView.bounds.height) else { return }

        // O(n) reindex handled via coordinator's newOrder
        var viewsByWorkspace: [String: [WorkspaceItemView]] = [:]
        for view in itemViews { viewsByWorkspace[view.workspace, default: []].append(view) }
        for (i, ws) in newOrder.enumerated() {
            guard var queue = viewsByWorkspace[ws], !queue.isEmpty else { continue }
            let view = queue.removeFirst()
            viewsByWorkspace[ws] = queue
            view.index = i
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            for view in itemViews where view !== dragging {
                view.animator().frame = WindowLayout.expandedFrame(
                    for: view.index, display: display, windowHeight: backgroundView.bounds.height
                )
            }
        }

        onOrderChanged?(workspaces)
    }

    private func handleDragEnd() {
        guard let dragging = draggingView else { return }
        let finalIndex = drag.end() ?? dragging.index
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            dragging.animator().frame = WindowLayout.expandedFrame(
                for: finalIndex, display: display, windowHeight: backgroundView.bounds.height
            )
        }
        draggingView = nil
    }
}
