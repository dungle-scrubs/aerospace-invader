import Cocoa
import Carbon.HIToolbox

// MARK: - State Management

class OrderManager {
    static let shared = OrderManager()
    private let configDir = NSHomeDirectory() + "/.config/aerospace-ui"
    private let orderFile: String

    private init() {
        orderFile = configDir + "/order.json"
        ensureConfigDir()
    }

    private func ensureConfigDir() {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
    }

    func loadOrder() -> [String] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: orderFile)),
              let order = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return order
    }

    func saveOrder(_ order: [String]) {
        guard let data = try? JSONEncoder().encode(order) else { return }
        try? data.write(to: URL(fileURLWithPath: orderFile))
    }

    // Merge saved order with current non-empty workspaces
    // Preserves saved order for existing workspaces, appends new ones
    func mergeWithCurrent(_ current: [String]) -> [String] {
        let saved = loadOrder()
        let currentSet = Set(current)

        // Keep saved items that still exist
        var result = saved.filter { currentSet.contains($0) }
        let resultSet = Set(result)

        // Append new workspaces not in saved order
        for ws in current {
            if !resultSet.contains(ws) {
                result.append(ws)
            }
        }

        return result
    }
}

// MARK: - Aerospace API

class AerospaceAPI {
    static let aerospacePath = "/opt/homebrew/bin/aerospace"

    // Check if aerospace is enabled by trying to list workspaces
    // If it fails, enable aerospace
    static func ensureEnabled() -> Bool {
        // Try a simple command to check if aerospace is responding
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: aerospacePath)
        checkTask.arguments = ["list-workspaces", "--focused"]

        let pipe = Pipe()
        checkTask.standardOutput = pipe
        checkTask.standardError = FileHandle.nullDevice

        do {
            try checkTask.run()
            checkTask.waitUntilExit()
        } catch {
            // Aerospace not running at all, try to enable
            return enableAerospace()
        }

        // If exit code is non-zero or no output, try enabling
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if checkTask.terminationStatus == 0 && !output.isEmpty {
            return true
        }

        return enableAerospace()
    }

    private static func enableAerospace() -> Bool {
        fputs("Aerospace not responding, enabling...\n", stderr)
        let enableTask = Process()
        enableTask.executableURL = URL(fileURLWithPath: aerospacePath)
        enableTask.arguments = ["enable", "on"]
        enableTask.standardOutput = FileHandle.nullDevice
        enableTask.standardError = FileHandle.nullDevice

        do {
            try enableTask.run()
            enableTask.waitUntilExit()
            // Give it a moment to initialize
            Thread.sleep(forTimeInterval: 0.5)
            return true
        } catch {
            fputs("Failed to enable aerospace\n", stderr)
            return false
        }
    }

    static func getNonEmptyWorkspaces() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: aerospacePath)
        task.arguments = ["list-workspaces", "--monitor", "all", "--empty", "no"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func getCurrentWorkspace() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: aerospacePath)
        task.arguments = ["list-workspaces", "--focused"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func switchToWorkspace(_ ws: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: aerospacePath)
        task.arguments = ["workspace", ws]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    static func getBindings(mode: String) -> [String: String]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: aerospacePath)
        task.arguments = ["config", "--get", "mode.\(mode).binding", "--json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }
}

// MARK: - Hotkey Manager

class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeyRefs: [EventHotKeyRef?] = []
    var onOptO: (() -> Void)?
    var onOptI: (() -> Void)?
    var onOptPeriod: (() -> Void)?

    private init() {}

    func register() {
        // Install handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotkeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)

            DispatchQueue.main.async {
                switch hotkeyID.id {
                case 1: HotkeyManager.shared.onOptO?()
                case 2: HotkeyManager.shared.onOptI?()
                case 3: HotkeyManager.shared.onOptPeriod?()
                default: break
                }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)

        // Register opt+o (id: 1)
        var hotkeyID1 = EventHotKeyID(signature: OSType(0x4B565354), id: 1) // "KVST"
        var hotkeyRef1: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_O), UInt32(optionKey), hotkeyID1, GetApplicationEventTarget(), 0, &hotkeyRef1)
        hotkeyRefs.append(hotkeyRef1)

        // Register opt+i (id: 2)
        var hotkeyID2 = EventHotKeyID(signature: OSType(0x4B565354), id: 2)
        var hotkeyRef2: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_I), UInt32(optionKey), hotkeyID2, GetApplicationEventTarget(), 0, &hotkeyRef2)
        hotkeyRefs.append(hotkeyRef2)

        // Register opt+period (id: 3) for expand
        var hotkeyID3 = EventHotKeyID(signature: OSType(0x4B565354), id: 3)
        var hotkeyRef3: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_Period), UInt32(optionKey), hotkeyID3, GetApplicationEventTarget(), 0, &hotkeyRef3)
        hotkeyRefs.append(hotkeyRef3)

        fputs("Hotkeys registered: ⌥O, ⌥I, ⌥.\n", stderr)
    }

    func unregister() {
        for ref in hotkeyRefs {
            if let r = ref {
                UnregisterEventHotKey(r)
            }
        }
        hotkeyRefs.removeAll()
    }
}

// MARK: - Workspace Navigator

class WorkspaceNavigator {
    static let shared = WorkspaceNavigator()

    private init() {}

    // Get current index in ordered list
    private func getCurrentIndex(in order: [String], current: String?) -> Int {
        guard let ws = current, let idx = order.firstIndex(of: ws) else { return 0 }
        return idx
    }

    // Navigate backward (⌥O)
    func back() -> (order: [String], current: String?) {
        let nonEmpty = AerospaceAPI.getNonEmptyWorkspaces()
        let order = OrderManager.shared.mergeWithCurrent(nonEmpty)
        OrderManager.shared.saveOrder(order)

        guard !order.isEmpty else { return ([], nil) }

        let current = AerospaceAPI.getCurrentWorkspace()
        let idx = getCurrentIndex(in: order, current: current)
        let newIdx = idx > 0 ? idx - 1 : order.count - 1
        let target = order[newIdx]

        AerospaceAPI.switchToWorkspace(target)
        return (order, target)
    }

    // Navigate forward (⌥I)
    func forward() -> (order: [String], current: String?) {
        let nonEmpty = AerospaceAPI.getNonEmptyWorkspaces()
        let order = OrderManager.shared.mergeWithCurrent(nonEmpty)
        OrderManager.shared.saveOrder(order)

        guard !order.isEmpty else { return ([], nil) }

        let current = AerospaceAPI.getCurrentWorkspace()
        let idx = getCurrentIndex(in: order, current: current)
        let newIdx = idx < order.count - 1 ? idx + 1 : 0
        let target = order[newIdx]

        AerospaceAPI.switchToWorkspace(target)
        return (order, target)
    }
}

// MARK: - Shared Styling

struct Style {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    static let smallFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let bgColor = NSColor(white: 0.1, alpha: 0.95)
    static let borderColor = NSColor(red: 0, green: 1, blue: 0, alpha: 0.6)
    static let activeColor = NSColor(red: 0, green: 1, blue: 0, alpha: 1)
    static let inactiveColor = NSColor(white: 0.5, alpha: 1)
    static let textColor = NSColor.white
}

// MARK: - Workspace Item View (unified pill/tile)

class WorkspaceItemView: NSView {
    let workspace: String
    var index: Int
    var isActive: Bool = false {
        didSet { updateAppearance() }
    }
    var isExpanded: Bool = false

    var onClick: ((String) -> Void)?
    var onDragStart: (() -> Void)?
    var onDragMove: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?

    private var label: NSTextField!
    private var isDragging = false
    private var dragOffset: NSPoint = .zero
    private var mouseDownLocation: NSPoint = .zero

    init(workspace: String, index: Int) {
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

    func updateAppearance() {
        if isExpanded {
            // Expanded tile style
            layer?.cornerRadius = 8
            if isActive {
                layer?.backgroundColor = NSColor(red: 0, green: 0.7, blue: 0.3, alpha: 1).cgColor
                layer?.borderColor = Style.activeColor.cgColor
                layer?.borderWidth = 2
            } else {
                layer?.backgroundColor = NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1).cgColor
                layer?.borderWidth = 0
            }
            label.textColor = .white
            label.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
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

    override func mouseDown(with event: NSEvent) {
        if isExpanded {
            isDragging = true
            let loc = convert(event.locationInWindow, from: nil)
            dragOffset = NSPoint(x: loc.x, y: loc.y)
            mouseDownLocation = superview?.convert(event.locationInWindow, from: nil) ?? .zero
            superview?.addSubview(self)
            onDragStart?()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                self.animator().alphaValue = 0.85
                self.layer?.shadowColor = NSColor.black.cgColor
                self.layer?.shadowOpacity = 0.5
                self.layer?.shadowRadius = 12
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, isExpanded, let sv = superview else { return }
        let loc = sv.convert(event.locationInWindow, from: nil)
        frame.origin = NSPoint(x: loc.x - dragOffset.x, y: loc.y - dragOffset.y)
        onDragMove?(NSPoint(x: frame.midX, y: frame.midY))
    }

    override func mouseUp(with event: NSEvent) {
        if isExpanded && isDragging {
            let mouseUpLocation = superview?.convert(event.locationInWindow, from: nil) ?? .zero
            let distance = hypot(mouseUpLocation.x - mouseDownLocation.x, mouseUpLocation.y - mouseDownLocation.y)

            isDragging = false
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

    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: - Unified Workspace Window

class WorkspaceWindow: NSPanel {
    enum Mode { case compact, expanded }

    var workspaces: [String] = []
    var currentWorkspace: String?
    var mode: Mode = .compact

    var onSelectWorkspace: ((String) -> Void)?
    var onOrderChanged: (([String]) -> Void)?
    var onCollapse: (() -> Void)?

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

    init() {
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

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 && mode == .expanded { // Escape
            fadeOut()
        } else {
            super.keyDown(with: event)
        }
    }

    func show(workspaces: [String], current: String?, autoHide: Bool = true) {
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

    func expand() {
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

    func collapse() {
        removeClickOutsideMonitor()
        mode = .compact

        for item in itemViews {
            item.isExpanded = false
            item.updateAppearance()
        }

        layoutCompact(animated: true)
        onCollapse?()
    }

    func fadeOut() {
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


// MARK: - Which-Key Window

class WhichKeyWindow: NSPanel {
    init() {
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

    func show(mode: String) {
        guard let bindings = AerospaceAPI.getBindings(mode: mode) else {
            fputs("Failed to get bindings for mode: \(mode)\n", stderr)
            return
        }

        let grouped = groupBindings(bindings)
        rebuildUI(groups: grouped)
        makeKeyAndOrderFront(nil)

        // Dismiss on click outside or any key press (aerospace eats Esc first)
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
            self?.fadeOut()
        }
    }

    func fadeOut() {
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            fadeOut()
        }
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var workspaceWindow: WorkspaceWindow?
    var whichKeyWindow: WhichKeyWindow?

    var mode: String = "daemon"
    var modeArg: String?
    var isDaemon: Bool { mode == "daemon" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure aerospace is running (except for hide command)
        if mode != "hide" {
            if !AerospaceAPI.ensureEnabled() {
                fputs("Could not enable aerospace, exiting\n", stderr)
                NSApp.terminate(nil)
                return
            }
        }

        switch mode {
        case "daemon":
            startDaemon()
        case "tabs":
            showWorkspaceWindow(expanded: false, autoHide: true)
        case "expand":
            showWorkspaceWindow(expanded: true, autoHide: false)
        case "whichkey":
            showWhichKey(mode: modeArg ?? "service")
        case "hide":
            NSApp.terminate(nil)
        default:
            fputs("Unknown mode: \(mode)\n", stderr)
            fputs("Usage: aerospace-invader [daemon|tabs|expand|whichkey <mode>]\n", stderr)
            NSApp.terminate(nil)
        }
    }

    private func startDaemon() {
        fputs("Starting aerospace-invader daemon...\n", stderr)

        // Register hotkeys
        HotkeyManager.shared.onOptO = { [weak self] in
            self?.handleOptO()
        }
        HotkeyManager.shared.onOptI = { [weak self] in
            self?.handleOptI()
        }
        HotkeyManager.shared.onOptPeriod = { [weak self] in
            self?.handleOptPeriod()
        }
        HotkeyManager.shared.register()

        fputs("Daemon running. Press ⌥O (back), ⌥I (forward), ⌥. (expand).\n", stderr)
    }

    private func handleOptPeriod() {
        // If window is visible in compact mode, expand it with animation
        if let window = workspaceWindow, window.isVisible, window.mode == .compact {
            window.expand()
        }
    }

    private func handleOptO() {
        let (order, current) = WorkspaceNavigator.shared.back()
        guard !order.isEmpty else { return }
        showOrUpdateWorkspaceWindow(workspaces: order, current: current)
    }

    private func handleOptI() {
        let (order, current) = WorkspaceNavigator.shared.forward()
        guard !order.isEmpty else { return }
        showOrUpdateWorkspaceWindow(workspaces: order, current: current)
    }

    private func showOrUpdateWorkspaceWindow(workspaces: [String], current: String?) {
        if workspaceWindow == nil {
            workspaceWindow = createWorkspaceWindow()
        }
        workspaceWindow?.show(workspaces: workspaces, current: current, autoHide: true)
    }

    private func createWorkspaceWindow() -> WorkspaceWindow {
        let window = WorkspaceWindow()
        window.onSelectWorkspace = { [weak self] ws in
            AerospaceAPI.switchToWorkspace(ws)
            if self?.isDaemon == true {
                self?.workspaceWindow?.fadeOut()
            } else {
                NSApp.terminate(nil)
            }
        }
        window.onOrderChanged = { newOrder in
            OrderManager.shared.saveOrder(newOrder)
        }
        window.onCollapse = { [weak self] in
            // In daemon mode, fade out after collapse animation
            if self?.isDaemon == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.workspaceWindow?.fadeOut()
                }
            }
        }
        return window
    }

    private func showWorkspaceWindow(expanded: Bool, autoHide: Bool) {
        let current = AerospaceAPI.getNonEmptyWorkspaces()
        let ordered = OrderManager.shared.mergeWithCurrent(current)
        OrderManager.shared.saveOrder(ordered)
        let currentWs = AerospaceAPI.getCurrentWorkspace()

        workspaceWindow = createWorkspaceWindow()
        workspaceWindow?.show(workspaces: ordered, current: currentWs, autoHide: autoHide && !expanded)

        if expanded {
            // Small delay so initial layout happens first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.workspaceWindow?.expand()
            }
        }
    }

    private func showWhichKey(mode: String) {
        whichKeyWindow = WhichKeyWindow()
        whichKeyWindow?.show(mode: mode)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Daemon keeps running even with no windows
        return !isDaemon
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()

// Parse args
if CommandLine.arguments.count > 1 {
    delegate.mode = CommandLine.arguments[1]
}
if CommandLine.arguments.count > 2 {
    delegate.modeArg = CommandLine.arguments[2]
}

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
