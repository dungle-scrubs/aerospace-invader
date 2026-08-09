import Cocoa

/// Deep module that owns every overlay presentation concern — panel chrome, centering,
/// fade animation, and dismissal. Previously `WorkspaceWindow` and `WhichKeyWindow` each
/// configured an `NSPanel` (borderless, nonactivating, clear, shadow), centered themselves
/// with ad-hoc `NSScreen` math, and faded with duplicated `NSAnimationContext` blocks.
/// A fix to panel level or animation duration leaked in only one place.
///
/// Now one module owns the chrome and lifecycle; the two windows are content adapters that
/// supply a view hierarchy and a `DismissalPolicy`. Two adapters justify the seam, and a
/// third overlay (search, help) would reuse it for free.
///
/// `OverlayShell` is intentionally style-less: colors stay in `Style` so the shell can
/// stay AppKit-agnostic about the dark-green aesthetic, while `Style.Overlay` groups the
/// overlay-specific constants in one place.
public enum OverlayShell {
    // MARK: - Panel factory

    /// Common chrome for every overlay panel. Callers still set `level` themselves
    /// (`.floating` vs `.popUpMenu`) because the shell doesn't decide z-order.
    public static func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    // MARK: - Geometry

    public enum Position {
        case centered
        case bottomTrailing
    }

    /// Window frame for a content size at the requested position on the main screen.
    public static func frame(for contentSize: CGSize, position: Position) -> NSRect? {
        guard let screen = NSScreen.main else {
            fputs("OverlayShell: no main screen available for layout\n", stderr)
            return nil
        }
        switch position {
        case .centered:
            let vf = screen.visibleFrame
            return NSRect(
                x: vf.midX - contentSize.width / 2,
                y: vf.midY - contentSize.height / 2,
                width: contentSize.width,
                height: contentSize.height
            )
        case .bottomTrailing:
            let vf = screen.visibleFrame
            let sf = screen.frame
            return NSRect(
                x: sf.maxX - contentSize.width - 20,
                y: vf.minY + 20,
                width: contentSize.width,
                height: contentSize.height
            )
        }
    }

    // MARK: - Animation

    /// Fade a window out and invoke completion on the main queue.
    public static func fadeOut(_ window: NSWindow, duration: TimeInterval = 0.2, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
            completion()
        })
    }

    /// Fade a window in from transparent.
    public static func fadeIn(_ window: NSWindow, duration: TimeInterval = 0.2) {
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            window.animator().alphaValue = 1
        }
    }

    // MARK: - Click-outside

    /// Install a global mouse-down monitor that fires when a click lands outside `window`.
    /// Returns an opaque token to pass to `removeMonitor`. This is the `NSEvent`-based path
    /// (less invasive than a `CGEvent` tap) and is now the single implementation for both
    /// overlays — WhichKeyWindow's CGEvent tap for dismiss is still available for mode-poll
    /// removal but click-outside uses this single path.
    public static func installClickOutsideMonitor(for window: NSWindow, handler: @escaping () -> Void) -> Any {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            let loc = NSEvent.mouseLocation
            if !window.frame.contains(loc) { handler() }
        } as Any
    }

    public static func removeMonitor(_ token: Any?) {
        if let token = token { NSEvent.removeMonitor(token) }
    }
}

// MARK: - Style grouping for overlays

public extension Style {
    /// Overlay-specific style group — one place for panel chrome constants so a design
    /// tweak (corner radius, border width) touches one module instead of two windows.
    enum Overlay {
        public static var background: NSColor { Style.bgColor }
        public static var border: NSColor { Style.windowBorderColor }
        public static var accentBorder: NSColor { Style.borderColor }
        public static var cornerRadius: CGFloat { 8 }
        public static var whichKeyCornerRadius: CGFloat { 10 }
        public static var borderWidth: CGFloat { 1 }
        public static var whichKeyBorderWidth: CGFloat { 2 }
    }
}
