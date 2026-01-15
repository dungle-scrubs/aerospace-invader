import Testing
@testable import AerospaceInvaderCore

@Suite("OrderManager")
struct OrderManagerTests {

    // MARK: - merge(saved:current:) tests

    @Test("preserves existing order")
    func mergePreservesExistingOrder() {
        let saved = ["A", "B", "C"]
        let current = ["A", "B", "C"]

        let result = OrderManager.merge(saved: saved, current: current)

        #expect(result == ["A", "B", "C"])
    }

    @Test("appends new workspaces")
    func mergeAppendsNewWorkspaces() {
        let saved = ["A", "B"]
        let current = ["A", "B", "C", "D"]

        let result = OrderManager.merge(saved: saved, current: current)

        #expect(result == ["A", "B", "C", "D"])
    }

    @Test("removes missing workspaces")
    func mergeRemovesMissingWorkspaces() {
        let saved = ["A", "B", "C", "D"]
        let current = ["A", "C"]

        let result = OrderManager.merge(saved: saved, current: current)

        #expect(result == ["A", "C"])
    }

    @Test("preserves custom order for existing")
    func mergePreservesCustomOrderForExisting() {
        // User reordered B before A
        let saved = ["B", "A", "C"]
        let current = ["A", "B", "C"]

        let result = OrderManager.merge(saved: saved, current: current)

        // Custom order should be preserved
        #expect(result == ["B", "A", "C"])
    }

    @Test("handles new workspaces with custom order")
    func mergeHandlesNewWorkspacesWithCustomOrder() {
        let saved = ["C", "A"]
        let current = ["A", "B", "C", "D"]

        let result = OrderManager.merge(saved: saved, current: current)

        // Preserved order first, then new ones in their original order
        #expect(result == ["C", "A", "B", "D"])
    }

    @Test("handles empty saved")
    func mergeEmptySaved() {
        let saved: [String] = []
        let current = ["A", "B", "C"]

        let result = OrderManager.merge(saved: saved, current: current)

        #expect(result == ["A", "B", "C"])
    }

    @Test("handles empty current")
    func mergeEmptyCurrent() {
        let saved = ["A", "B", "C"]
        let current: [String] = []

        let result = OrderManager.merge(saved: saved, current: current)

        #expect(result == [])
    }

    @Test("handles both empty")
    func mergeBothEmpty() {
        let saved: [String] = []
        let current: [String] = []

        let result = OrderManager.merge(saved: saved, current: current)

        #expect(result == [])
    }

    @Test("handles complete replacement")
    func mergeCompleteReplacement() {
        let saved = ["X", "Y", "Z"]
        let current = ["A", "B", "C"]

        let result = OrderManager.merge(saved: saved, current: current)

        // None of saved exist anymore, so just return current order
        #expect(result == ["A", "B", "C"])
    }

    @Test("produces no duplicates")
    func mergeNoDuplicates() {
        let saved = ["A", "B", "A", "C"]  // Malformed saved with duplicate
        let current = ["A", "B", "C"]

        let result = OrderManager.merge(saved: saved, current: current)

        // Should not have duplicates
        #expect(Set(result).count == result.count)
    }
}
