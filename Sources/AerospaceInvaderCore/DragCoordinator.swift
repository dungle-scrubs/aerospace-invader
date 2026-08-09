import Cocoa

/// Deep drag module that owns the reorder state machine — point→index mapping and the
/// `WorkspaceDisplay.reorder` call. Previously `WorkspaceWindow` interleaved
/// `draggingView` state, `indexForPoint` via `expandedGrid`, `display.reorder(...)`,
/// O(n) reindex of `itemViews`, and `NSAnimationContext` in one method. Now the
/// coordinate math + reorder decision is isolated and testable without an `NSPanel`.
///
/// The coordinator owns the drag session (`begin`/`move`/`end`) and delegates view
/// reindexing back to the panel via the `onReordered` callback so AppKit stays at the
/// boundary.
public final class DragCoordinator {
    private let display: WorkspaceDisplay
    private var draggingIndex: Int?

    public init(display: WorkspaceDisplay) {
        self.display = display
    }

    /// Begin a drag session for the item at `index`.
    public func begin(at index: Int) {
        draggingIndex = index
    }

    /// Handle a drag move to `point` inside a window with `windowHeight`.
    /// - Returns: The new order if reorder occurred, plus the move `targetIndex`, otherwise nil.
    @discardableResult
    public func move(to point: CGPoint, windowHeight: CGFloat) -> (order: [String], targetIndex: Int)? {
        guard let current = draggingIndex else { return nil }
        let target = WindowLayout.expandedIndex(for: point, display: display, windowHeight: windowHeight)
        guard let newOrder = display.reorder(from: current, to: target) else { return nil }
        draggingIndex = target
        return (newOrder, target)
    }

    /// End the session and return the final dragged index (for the drop animation).
    public func end() -> Int? {
        let idx = draggingIndex
        draggingIndex = nil
        return idx
    }

    /// Whether a drag is in progress.
    public var isDragging: Bool { draggingIndex != nil }

    /// Current dragged index without ending.
    public var currentIndex: Int? { draggingIndex }
}
