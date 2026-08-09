import Cocoa
import CoreGraphics
import Foundation

// MARK: - Display state

/// Pure value type representing the OSD's logical state. Independent of AppKit so
/// ordering, focus, and mode transitions can be unit-tested without an NSWindow or NSScreen.
public struct WorkspaceDisplayState: Equatable {
    /// Ordered workspace names as displayed.
    public var workspaces: [String]
    /// Currently focused workspace name.
    public var focused: String?
    /// Compact pill bar vs expanded grid.
    public var mode: WorkspaceWindow.Mode

    public init(workspaces: [String], focused: String?, mode: WorkspaceWindow.Mode = .compact) {
        self.workspaces = workspaces
        self.focused = focused
        self.mode = mode
    }

    /// Whether the given workspace is the active one.
    public func isActive(_ workspace: String) -> Bool {
        workspace == focused
    }
}

// MARK: - Compact geometry

/// Pure geometry for the compact pill bar. The text-measuring seam is injected so the
/// layout math can be tested without AppKit — production passes
/// `NSString.size(withAttributes:)` via `Style.font`, tests pass a stub.
public struct CompactLayout {
    public let workspaces: [String]
    public let sizer: (String) -> CGFloat

    public let compactHeight: CGFloat
    public let compactPadding: CGFloat
    public let compactSpacing: CGFloat
    public let outerPadding: CGFloat

    public init(
        workspaces: [String],
        sizer: @escaping (String) -> CGFloat,
        compactHeight: CGFloat = 28,
        compactPadding: CGFloat = 10,
        compactSpacing: CGFloat = 4,
        outerPadding: CGFloat = 8
    ) {
        self.workspaces = workspaces
        self.sizer = sizer
        self.compactHeight = compactHeight
        self.compactPadding = compactPadding
        self.compactSpacing = compactSpacing
        self.outerPadding = outerPadding
    }

    /// Width of each pill including internal padding.
    public var pillWidths: [CGFloat] {
        workspaces.map { sizer($0) + compactPadding * 2 }
    }

    /// Total window width for the current workspaces.
    public var totalWidth: CGFloat {
        guard !workspaces.isEmpty else { return outerPadding * 2 }
        let pills = pillWidths.reduce(0) { $0 + $1 + compactSpacing }
        // pills already includes trailing spacing for each item — remove last spacing
        // then add outer chrome (matching WorkspaceWindow.layoutCompact's 16 + 8)
        return 16 + pills - compactSpacing + 8
    }

    public var windowHeight: CGFloat { compactHeight + 16 }

    /// Window frame centered horizontally at the top of the given visible frame.
    public func windowFrame(in visibleFrame: CGRect) -> CGRect {
        let w = totalWidth
        let h = windowHeight
        let x = visibleFrame.midX - w / 2
        let y = visibleFrame.maxY - h - 8
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Item frames within a window anchored at the origin.
    public func itemFrames() -> [CGRect] {
        let y: CGFloat = outerPadding
        var x: CGFloat = outerPadding
        var frames: [CGRect] = []
        for width in pillWidths {
            frames.append(CGRect(x: x, y: y, width: width, height: compactHeight))
            x += width + compactSpacing
        }
        return frames
    }
}

// MARK: - WorkspaceDisplay — the deep module behind WorkspaceWindow

/// Deep module that owns every display decision — ordering, focus, mode, ordering
/// mutations (drag reorder), and geometry. The window is a thin adapter that renders
/// this state and forwards intents back into the display.
///
/// Depth comes from collapsing four concerns into one seam:
/// compact geometry, expanded GridLayout, drag state machine, and order invariant.
public final class WorkspaceDisplay {
    // MARK: Configuration

    /// Layout constants, mirroring the former WorkspaceWindow private lets. Centralized
    /// so a test can assert frames without reaching into AppKit.
    public struct LayoutConfig {
        public var compactHeight: CGFloat = 28
        public var compactPadding: CGFloat = 10
        public var compactSpacing: CGFloat = 4
        public var outerPadding: CGFloat = 8
        public var expandedItemSize: CGFloat = 100
        public var expandedSpacing: CGFloat = 12
        public var expandedPadding: CGFloat = 20
        public var expandedHeaderHeight: CGFloat = 28

        public static let `default` = LayoutConfig()
    }

    private(set) public var state: WorkspaceDisplayState
    public let config: LayoutConfig
    /// Text-width sizer injected for testability.
    private let sizer: (String) -> CGFloat

    public init(
        workspaces: [String] = [],
        focused: String? = nil,
        mode: WorkspaceWindow.Mode = .compact,
        config: LayoutConfig = .default,
        sizer: @escaping (String) -> CGFloat = WorkspaceDisplay.defaultSizer
    ) {
        self.state = WorkspaceDisplayState(workspaces: workspaces, focused: focused, mode: mode)
        self.config = config
        self.sizer = sizer
    }

    /// Default sizer using AppKit's monospaced font metrics, matching the former window.
    public static let defaultSizer: (String) -> CGFloat = { text in
        (text as NSString).size(withAttributes: [.font: Style.font]).width
    }

    // MARK: State mutations — single seam for ordering

    /// Replace the entire workspace list and focus. Used when the system reports fresh state.
    public func update(workspaces: [String], focused: String?) {
        state.workspaces = workspaces
        state.focused = focused
    }

    /// Reorder by index — the only ordering mutation. Callers (drag handling) map points to
    /// indices via `expandedGrid` and call this; no linear search by workspace name.
    /// - Returns: The new order, or nil if the indices were out of bounds or equal.
    @discardableResult
    public func reorder(from sourceIndex: Int, to targetIndex: Int) -> [String]? {
        guard sourceIndex != targetIndex,
              sourceIndex >= 0, sourceIndex < state.workspaces.count,
              targetIndex >= 0, targetIndex < state.workspaces.count else {
            return nil
        }
        let item = state.workspaces.remove(at: sourceIndex)
        state.workspaces.insert(item, at: targetIndex)
        return state.workspaces
    }

    /// Move a workspace identified by name to a target index. Preserved for callers that
    /// still hold names — implemented via index lookup, not per-item linear search.
    @discardableResult
    public func reorder(workspace: String, to targetIndex: Int) -> [String]? {
        guard let source = state.workspaces.firstIndex(of: workspace) else { return nil }
        return reorder(from: source, to: targetIndex)
    }

    public func expand() { state.mode = .expanded }
    public func collapse() { state.mode = .compact }
    public func toggleMode() { state.mode = state.mode == .compact ? .expanded : .compact }

    public var isExpanded: Bool { state.mode == .expanded }
    public var workspaces: [String] { state.workspaces }
    public var focused: String? { state.focused }

    // MARK: Geometry — single place for every frame

    public var compactLayout: CompactLayout {
        CompactLayout(
            workspaces: state.workspaces,
            sizer: sizer,
            compactHeight: config.compactHeight,
            compactPadding: config.compactPadding,
            compactSpacing: config.compactSpacing,
            outerPadding: config.outerPadding
        )
    }

    public var expandedGrid: GridLayout {
        GridLayout(
            itemCount: state.workspaces.count,
            itemSize: config.expandedItemSize,
            spacing: config.expandedSpacing,
            padding: config.expandedPadding,
            headerHeight: config.expandedHeaderHeight
        )
    }
}
