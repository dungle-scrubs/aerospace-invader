import Cocoa
import CoreGraphics

public class WhichKeyWindow: NSPanel {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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
    }

    public func show(mode: String) {
        guard let bindings = AerospaceAPI.getBindings(mode: mode) else {
            fputs("Failed to get bindings for mode: \(mode)\n", stderr)
            return
        }

        let grouped = groupBindings(bindings)
        rebuildUI(groups: grouped)
        makeKeyAndOrderFront(nil)

        // Use CGEventTap to catch keys at a lower level than AeroSpace
        setupEventTap()
    }

    private func setupEventTap() {
        // Create a callback that references self via pointer
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let window = Unmanaged<WhichKeyWindow>.fromOpaque(userInfo).takeUnretainedValue()

            // Note: Key events in service mode are intercepted by AeroSpace before
            // reaching this tap. The aerospace config handles closing the window
            // when exiting service mode. This tap catches mouse clicks to dismiss.
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == 53 { // Escape
                    DispatchQueue.main.async {
                        window.fadeOut()
                    }
                }
            } else if type == .leftMouseDown || type == .rightMouseDown {
                DispatchQueue.main.async {
                    window.fadeOut()
                }
            }

            return Unmanaged.passUnretained(event)
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        // Listen for key down and mouse clicks
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

        // Create a passive event tap (listenOnly doesn't intercept)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPointer
        ) else {
            fputs("Failed to create event tap - accessibility permissions may be required\n", stderr)
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

    public func fadeOut() {
        cleanupEventTap()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: {
            NSApp.terminate(nil)
        })
    }

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

    private func formatKey(_ key: String) -> String {
        var r = key
        r = r.replacingOccurrences(of: "shift-ctrl-alt-", with: "⌃⌥⇧")
        r = r.replacingOccurrences(of: "ctrl-alt-", with: "⌃⌥")
        r = r.replacingOccurrences(of: "alt-shift-", with: "⌥⇧")
        r = r.replacingOccurrences(of: "alt-", with: "⌥")
        r = r.replacingOccurrences(of: "shift-", with: "⇧")
        r = r.replacingOccurrences(of: "ctrl-", with: "⌃")
        r = r.replacingOccurrences(of: "cmd-", with: "⌘")
        r = r.replacingOccurrences(of: "backspace", with: "⌫")
        r = r.replacingOccurrences(of: "esc", with: "Esc")
        r = r.replacingOccurrences(of: "semicolon", with: ";")
        r = r.replacingOccurrences(of: "comma", with: ",")
        r = r.replacingOccurrences(of: "slash", with: "/")
        return r
    }

    private func formatCmd(_ cmd: String) -> String {
        var r = cmd
        r = r.replacingOccurrences(of: "; mode main", with: "")
        r = r.replacingOccurrences(of: "flatten-workspace-tree", with: "flatten")
        r = r.replacingOccurrences(of: "close-all-windows-but-current", with: "close others")
        r = r.replacingOccurrences(of: "layout floating tiling", with: "toggle float")
        r = r.replacingOccurrences(of: "reload-config", with: "reload")
        r = r.replacingOccurrences(of: "join-with ", with: "join ")
        r = r.replacingOccurrences(of: "enable toggle", with: "toggle enable")
        return r
    }

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

        guard let screen = NSScreen.main else { return }
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
            // Header
            let header = NSTextField(labelWithString: group.name)
            header.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            header.textColor = NSColor(white: 0.5, alpha: 1)
            yPos -= headerHeight
            header.frame = NSRect(x: padding, y: yPos, width: width - padding * 2, height: headerHeight)
            contentView?.addSubview(header)

            // Items
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
