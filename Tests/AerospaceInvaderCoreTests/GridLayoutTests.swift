import CoreGraphics
import Testing

@testable import AerospaceInvaderCore

@Suite("GridLayout")
struct GridLayoutTests {

    private func grid(_ count: Int) -> GridLayout {
        GridLayout(itemCount: count, itemSize: 100, spacing: 12, padding: 20, headerHeight: 28)
    }

    // MARK: - Columns / rows

    @Test("columns cap at the maximum")
    func columnsCap() {
        #expect(grid(3).columns == 3)
        #expect(grid(5).columns == 5)
        #expect(grid(7).columns == GridLayout.maxColumns)
        #expect(GridLayout.maxColumns == 5)
    }

    @Test("columns is at least one even with no items")
    func columnsFloor() {
        #expect(grid(0).columns == 1)
    }

    @Test("rows wrap beyond the column cap")
    func rowsWrap() {
        #expect(grid(0).rows == 0)
        #expect(grid(5).rows == 1)
        #expect(grid(6).rows == 2)
        #expect(grid(11).rows == 3)
    }

    // MARK: - Content size

    @Test("content size accounts for padding, spacing, and header")
    func contentSize() {
        let size = grid(3).contentSize
        // 3 * (100 + 12) - 12 + 20*2 = 336 - 12 + 40 = 364 wide
        #expect(size.width == 364)
        // 1 * (100 + 12) - 12 + 40 + 28 = 100 + 40 + 28 = 168 tall
        #expect(size.height == 168)
    }

    // MARK: - Frame / hit-test round trip

    @Test("indexForPoint recovers the index at each item's center")
    func frameHitTestRoundTrip() {
        let g = grid(7)
        let windowHeight = g.contentSize.height
        for index in 0..<7 {
            let frame = g.frame(forIndex: index, windowHeight: windowHeight)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            #expect(g.index(forPoint: center, windowHeight: windowHeight) == index)
        }
    }

    @Test("indexForPoint clamps out-of-bounds points to valid items")
    func hitTestClamps() {
        let g = grid(4)
        let windowHeight = g.contentSize.height
        #expect(g.index(forPoint: CGPoint(x: -500, y: windowHeight), windowHeight: windowHeight) == 0)
        #expect(g.index(forPoint: CGPoint(x: 5000, y: -5000), windowHeight: windowHeight) == 3)
    }
}
