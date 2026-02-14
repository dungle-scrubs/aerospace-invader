import Cocoa

/// A popup overlay that shows the keybindings for an AeroSpace mode (e.g. service, resize).
/// Auto-dismisses when the user exits the mode or presses Escape/clicks outside.
public class WhichKeyWindow: NSPanel {
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

        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    deinit {
        modeCheckTimer?.invalidate()
        cleanupEventTap()
    }

    /// Displays the which-key window for the given AeroSpace mode.
    /// - Parameter mode: The mode name (e.g. "service", "resize").
    public func show(mode: String) {
        guard let bindings = api.getBindings(mode: mode) else {
            fputs("Failed to get bindings for mode: \(mode)\n", stderr)
            return
        }

        targetMode = mode
        let grouped = groupBindings(bindings)
        rebuildUI(groups: grouped)
        makeKeyAndOrderFront(nil)

        setupEventTap()

        // Delay mode-check to let AeroSpace settle after entering the mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startModeCheckTimer()
        }
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
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let window = Unmanaged<WhichKeyWindow>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == 53 { // Escape
                    DispatchQueue.main.async { window.fadeOut() }
                }
            } else if type == .leftMouseDown || type == .rightMouseDown {
                DispatchQueue.main.async { window.fadeOut() }
            }

            return Unmanaged.passUnretained(event)
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
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

    /// Fades the window out, cleans up resources, and terminates the app.
    public func fadeOut() {
        modeCheckTimer?.invalidate()
        modeCheckTimer = nil
        cleanupEventTap()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: {
            NSApp.terminate(nil)
        })
    }

    // MARK: - Binding Categorization

    /// Modifier replacements used by `formatKey` — ordered longest-first to avoid partial matches.
    private static let keyReplacements: [(from: String, to: String)] = [
        ("shift-ctrl-alt-", "⌃⌥⇧"),
        ("ctrl-alt-", "⌃⌥"),
        ("alt-shift-", "⌥⇧"),
        ("alt-", "⌥"),
        ("shift-", "⇧"),
        ("ctrl-", "⌃"),
        ("cmd-", "⌘"),
        ("backspace", "⌫"),
        ("esc", "Esc"),
        ("semicolon", ";"),
        ("comma", ","),
        ("slash", "/")
    ]

    /// Command simplifications used by `formatCmd`.
    private static let cmdReplacements: [(from: String, to: String)] = [
        ("; mode main", ""),
        ("flatten-workspace-tree", "flatten"),
        ("close-all-windows-but-current", "close others"),
        ("layout floating tiling", "toggle float"),
        ("reload-config", "reload"),
        ("join-with ", "join "),
        ("enable toggle", "toggle enable")
    ]

    /// Groups bindings into categories for display.
    /// - Parameter bindings: Raw key → command mappings from AeroSpace.
    /// - Returns: Named groups with sorted items, in display order.
    private func groupBindings(_ bindings: [String: String]) -> [(name: String, items: [(key: String, cmd: String)])] {
        var groups: [String: [(key: String, cmd: String)]] = [
            "Movement": [], "Layout": [], "Actions": [], "Exit": []
        ]

        for (key, cmd) in bindings {
            let cat = categorize(key: key, cmd: cmd)
            groups[cat]?.append((key: key, cmd: cmd))
        }

        for cat in groups.keys {
            groups[cat]?.sort { $0.key < $1.key }
        }

        return ["Movement", "Layout", "Actions", "Exit"].compactMap { name in
            guard let items = groups[name], !items.isEmpty else { return nil }
            return (name: name, items: items)
        }
    }

    /// Categorizes a binding into Movement, Layout, Exit, or Actions.
    /// - Parameters:
    ///   - key: The key string (e.g. "h", "alt-shift-h").
    ///   - cmd: The command string (e.g. "focus left", "layout h_accordion").
    /// - Returns: Category name.
    private func categorize(key: String, cmd: String) -> String {
        if cmd.hasPrefix("move ") || cmd.hasPrefix("join-with ") || cmd.hasPrefix("focus ") {
            return "Movement"
        }
        if cmd.hasPrefix("layout ") || cmd.contains("fullscreen") {
            return "Layout"
        }
        if cmd.contains("mode main") && (key == "esc" || cmd.contains("reload")) {
            return "Exit"
        }
        return "Actions"
    }

    /// Converts modifier/key strings to readable symbols.
    /// - Parameter key: Raw key string from AeroSpace config.
    /// - Returns: Human-readable key representation.
    private func formatKey(_ key: String) -> String {
        var result = key
        for replacement in Self.keyReplacements {
            result = result.replacingOccurrences(of: replacement.from, with: replacement.to)
        }
        return result
    }

    /// Simplifies command strings for display.
    /// - Parameter cmd: Raw command string from AeroSpace config.
    /// - Returns: Shortened, human-readable command.
    private func formatCmd(_ cmd: String) -> String {
        var result = cmd
        for replacement in Self.cmdReplacements {
            result = result.replacingOccurrences(of: replacement.from, with: replacement.to)
        }
        return result
    }

    // MARK: - UI

    private func rebuildUI(groups: [(name: String, items: [(key: String, cmd: String)])]) {
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
        bg.layer?.backgroundColor = Style.bgColor.cgColor
        bg.layer?.cornerRadius = 10
        bg.layer?.borderColor = Style.borderColor.cgColor
        bg.layer?.borderWidth = 2
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
        sep.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
        contentView?.addSubview(sep)

        // Groups
        var yPos = height - padding - titleHeight - 8

        for group in groups {
            let header = NSTextField(labelWithString: group.name)
            header.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            header.textColor = NSColor(white: 0.5, alpha: 1)
            yPos -= headerHeight
            header.frame = NSRect(x: padding, y: yPos, width: width - padding * 2, height: headerHeight)
            contentView?.addSubview(header)

            for item in group.items {
                yPos -= lineHeight

                let keyLabel = NSTextField(labelWithString: formatKey(item.key))
                keyLabel.font = font
                keyLabel.textColor = NSColor(red: 1, green: 0.8, blue: 0, alpha: 1)
                keyLabel.frame = NSRect(x: padding + 8, y: yPos, width: 80, height: lineHeight)
                contentView?.addSubview(keyLabel)

                let cmdLabel = NSTextField(labelWithString: formatCmd(item.cmd))
                cmdLabel.font = font
                cmdLabel.textColor = NSColor(white: 0.7, alpha: 1)
                cmdLabel.lineBreakMode = .byTruncatingTail
                cmdLabel.frame = NSRect(x: padding + 100, y: yPos, width: width - padding - 108, height: lineHeight)
                contentView?.addSubview(cmdLabel)
            }

            yPos -= 8
        }
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            fadeOut()
        }
    }

    public override var canBecomeKey: Bool { true }
}
