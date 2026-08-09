import Carbon.HIToolbox
import Cocoa

/// A popup overlay that shows the keybindings for an AeroSpace mode (e.g. service, resize).
/// Auto-dismisses when the user exits the mode or presses Escape/clicks outside.
public final class WhichKeyWindow: NSPanel {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modeCheckTimer: Timer?
    private var targetMode: String?

    /// Reference to the aerospace API for mode polling.
    private let api: AerospaceCommandExecutor

    /// Creates a which-key window.
    /// - Parameter api: The aerospace API to use for fetching bindings and polling mode changes.
    public init(api: AerospaceCommandExecutor = AerospaceAPI.shared) {
        self.api = api
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        OverlayShell.configure(self)
        level = .popUpMenu
    }

    deinit {
        modeCheckTimer?.invalidate()
        cleanupEventTap()
    }

    /// Displays the which-key window for the given AeroSpace mode.
    /// - Parameter mode: The mode name (e.g. "service", "resize").
    /// - Returns: True if the window was shown; false if bindings couldn't be fetched, in which
    ///   case no window is created and the caller must decide how to terminate.
    @discardableResult
    public func show(mode: String) -> Bool {
        guard let bindings = api.getBindings(mode: mode) else {
            fputs("Failed to get bindings for mode: \(mode)\n", stderr)
            return false
        }

        targetMode = mode
        let grouped = BindingFormatter.group(bindings)
        rebuildUI(groups: grouped)
        makeKeyAndOrderFront(nil)

        setupEventTap()

        // Delay mode-check to let AeroSpace settle after entering the mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startModeCheckTimer()
        }
        return true
    }

    // MARK: - Mode Polling

    private func startModeCheckTimer() {
        modeCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self, let target = self.targetMode else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                guard let current = self.api.getCurrentMode(), current != target else { return }
                DispatchQueue.main.async {
                    self.fadeOut()
                }
            }
        }
    }

    // MARK: - Event Tap

    private func setupEventTap() {
        // Intentionally NOT tapping .keyDown: a session-wide keyboard tap would observe every
        // keystroke system-wide (a keylogger-shaped surface) just to catch Escape. Escape is
        // handled by this panel's keyDown override and by the mode-exit poll instead; the tap
        // watches only mouse-down, to dismiss on a click outside the overlay.
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let window = Unmanaged<WhichKeyWindow>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .leftMouseDown || type == .rightMouseDown {
                DispatchQueue.main.async { window.fadeOut() }
            }

            return Unmanaged.passUnretained(event)
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPointer
        ) else {
            fputs("Failed to create event tap — accessibility permissions may be required\n", stderr)
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func cleanupEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Fades the window out, cleans up resources, and terminates the app. Delegates
    /// animation to `OverlayShell` so both overlays share one fade path.
    public func fadeOut() {
        modeCheckTimer?.invalidate()
        modeCheckTimer = nil
        cleanupEventTap()
        OverlayShell.fadeOut(self, duration: 0.15) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - UI

    private func rebuildUI(groups: [BindingFormatter.Group]) {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let lineHeight: CGFloat = 20
        let headerHeight: CGFloat = 28
        let padding: CGFloat = 16
        let titleHeight: CGFloat = 28

        var totalLines = 0
        for g in groups { totalLines += g.items.count }

        let width: CGFloat = 360
        let height = titleHeight + CGFloat(totalLines) * lineHeight + CGFloat(groups.count) * (headerHeight + 8) + padding * 2

        guard let screen = NSScreen.main else {
            fputs("WhichKeyWindow: no main screen available for layout\n", stderr)
            return
        }
        let x = screen.frame.maxX - width - 20
        let y = screen.visibleFrame.minY + 20

        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        let bg = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = Style.Overlay.background.cgColor
        bg.layer?.cornerRadius = Style.Overlay.whichKeyCornerRadius
        bg.layer?.borderColor = Style.Overlay.accentBorder.cgColor
        bg.layer?.borderWidth = Style.Overlay.whichKeyBorderWidth
        contentView = bg

        // Title
        let title = NSTextField(labelWithString: "AeroSpace")
        title.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
        title.textColor = Style.activeColor
        title.alignment = .center
        title.frame = NSRect(x: padding, y: height - padding - 20, width: width - padding * 2, height: 20)
        contentView?.addSubview(title)

        // Separator
        let sep = NSView(frame: NSRect(x: padding, y: height - padding - titleHeight, width: width - padding * 2, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = Style.separatorColor.cgColor
        contentView?.addSubview(sep)

        // Groups
        var yPos = height - padding - titleHeight - 8

        for group in groups {
            let header = NSTextField(labelWithString: group.category.rawValue)
            header.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            header.textColor = Style.inactiveColor
            yPos -= headerHeight
            header.frame = NSRect(x: padding, y: yPos, width: width - padding * 2, height: headerHeight)
            contentView?.addSubview(header)

            for item in group.items {
                yPos -= lineHeight

                let keyLabel = NSTextField(labelWithString: BindingFormatter.formatKey(item.key))
                keyLabel.font = font
                keyLabel.textColor = Style.keyColor
                keyLabel.frame = NSRect(x: padding + 8, y: yPos, width: 80, height: lineHeight)
                contentView?.addSubview(keyLabel)

                let cmdLabel = NSTextField(labelWithString: BindingFormatter.formatCmd(item.cmd))
                cmdLabel.font = font
                cmdLabel.textColor = Style.secondaryTextColor
                cmdLabel.lineBreakMode = .byTruncatingTail
                cmdLabel.frame = NSRect(x: padding + 100, y: yPos, width: width - padding - 108, height: lineHeight)
                contentView?.addSubview(cmdLabel)
            }

            yPos -= 8
        }
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            fadeOut()
        }
    }

    public override var canBecomeKey: Bool { true }
}
