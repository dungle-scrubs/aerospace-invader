import CoreGraphics

/// Pure geometry for the expanded workspace grid: column count, item frames, and hit-testing.
/// Kept free of AppKit so the layout math (and the "max 5 columns" rule) has one owner and
/// can be unit-tested without a live window.
struct GridLayout {
    /// The grid never exceeds this many columns; extra items wrap to new rows.
    static let maxColumns = 5

    let itemCount: Int
    let itemSize: CGFloat
    let spacing: CGFloat
    let padding: CGFloat
    let headerHeight: CGFloat

    /// Number of columns for the current item count (at least 1, capped at `maxColumns`).
    var columns: Int { max(1, min(itemCount, GridLayout.maxColumns)) }

    /// Number of rows needed to hold every item.
    var rows: Int { itemCount == 0 ? 0 : (itemCount + columns - 1) / columns }

    /// Total content size, including padding on all sides and the header strip.
    var contentSize: CGSize {
        let width = CGFloat(columns) * (itemSize + spacing) - spacing + padding * 2
        let height = CGFloat(rows) * (itemSize + spacing) - spacing + padding * 2 + headerHeight
        return CGSize(width: width, height: height)
    }

    /// Frame for the item at `index` within a window of the given height (top-left origin grid,
    /// bottom-left coordinate space).
    func frame(forIndex index: Int, windowHeight: CGFloat) -> CGRect {
        let col = index % columns
        let row = index / columns
        let x = padding + CGFloat(col) * (itemSize + spacing)
        let y = windowHeight - padding - headerHeight - CGFloat(row + 1) * (itemSize + spacing) + spacing
        return CGRect(x: x, y: y, width: itemSize, height: itemSize)
    }

    /// The item index nearest to `point` within a window of the given height, clamped to a valid item.
    func index(forPoint point: CGPoint, windowHeight: CGFloat) -> Int {
        guard itemCount > 0 else { return 0 }
        let col = Int((point.x - padding) / (itemSize + spacing))
        let row = Int((windowHeight - padding - headerHeight - point.y) / (itemSize + spacing))
        let clampedCol = max(0, min(col, columns - 1))
        let clampedRow = max(0, row)
        let index = clampedRow * columns + clampedCol
        return max(0, min(index, itemCount - 1))
    }
}
