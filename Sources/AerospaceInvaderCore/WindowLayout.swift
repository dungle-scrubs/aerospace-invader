import Cocoa
import CoreGraphics

/// Deep layout module that owns every frame for the workspace OSD — compact pill bar and
/// expanded grid — without holding an `NSWindow` or `NSScreen`. Previously `WorkspaceWindow`
/// computed `windowFrame` + `backgroundView.frame` + each `item.frame` inline with duplicated
/// `NSAnimationContext` blocks and `NSScreen.main!.visibleFrame` captured inside the layout.
/// Now the math is pure: callers pass `visibleFrame` in, get frames out, and the panel only
/// applies them. That is the depth — one place for every rect, testable without AppKit.
public enum WindowLayout {
    // MARK: - Compact

    /// Window frame for the compact pill bar, centered at the top of `visibleFrame`.
    /// Delegates to `CompactLayout.windowFrame` so the 16+8 chrome stays in one place.
    public static func compactWindowFrame(display: WorkspaceDisplay, in visibleFrame: CGRect) -> CGRect {
        display.compactLayout.windowFrame(in: visibleFrame)
    }

    /// Size of the compact window content (background view) — mirrors `CompactLayout` height.
    public static func compactContentSize(display: WorkspaceDisplay) -> CGSize {
        let c = display.compactLayout
        return CGSize(width: c.totalWidth, height: c.windowHeight)
    }

    /// Pill widths for the compact bar — one source, not recomputed in the panel.
    public static func compactPillWidths(display: WorkspaceDisplay) -> [CGFloat] {
        display.compactLayout.pillWidths
    }

    /// Frames for every pill inside a compact window anchored at the origin.
    /// Matches `WorkspaceWindow.layoutCompact`'s `xPos = 8, yPos = 8` loop.
    public static func compactItemFrames(display: WorkspaceDisplay) -> [CGRect] {
        let pillWidths = compactPillWidths(display: display)
        let h = display.config.compactHeight
        let spacing = display.config.compactSpacing
        var frames: [CGRect] = []
        var x: CGFloat = 8
        let y: CGFloat = 8
        for w in pillWidths {
            frames.append(CGRect(x: x, y: y, width: w, height: h))
            x += w + spacing
        }
        return frames
    }

    // MARK: - Expanded

    /// Window frame for the expanded grid, centered in `visibleFrame`.
    /// Mirrors `WorkspaceWindow.layoutExpanded`'s `midX - width/2` centering.
    public static func expandedWindowFrame(display: WorkspaceDisplay, in visibleFrame: CGRect) -> CGRect? {
        guard !display.state.workspaces.isEmpty else { return nil }
        let content = display.expandedGrid.contentSize
        let x = visibleFrame.midX - content.width / 2
        let y = visibleFrame.midY - content.height / 2
        return CGRect(x: x, y: y, width: content.width, height: content.height)
    }

    /// Content size for the expanded grid (background view = window).
    public static func expandedContentSize(display: WorkspaceDisplay) -> CGSize {
        display.expandedGrid.contentSize
    }

    /// Frame for the item at `index` inside an expanded window of `windowHeight`.
    public static func expandedFrame(
        for index: Int,
        display: WorkspaceDisplay,
        windowHeight: CGFloat
    ) -> CGRect {
        display.expandedGrid.frame(forIndex: index, windowHeight: windowHeight)
    }

    /// Index nearest to `point` inside an expanded window of the given `windowHeight`.
    public static func expandedIndex(for point: CGPoint, display: WorkspaceDisplay, windowHeight: CGFloat) -> Int {
        display.expandedGrid.index(forPoint: point, windowHeight: windowHeight)
    }
}
