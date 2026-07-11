@testable import AerospaceInvaderCore
import Foundation
import Testing

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
        let saved = ["B", "A", "C"]
        let current = ["A", "B", "C"]

        let result = OrderManager.merge(saved: saved, current: current)

        #expect(result == ["B", "A", "C"])
    }

    @Test("handles new workspaces with custom order")
    func mergeHandlesNewWorkspacesWithCustomOrder() {
        let saved = ["C", "A"]
        let current = ["A", "B", "C", "D"]

        let result = OrderManager.merge(saved: saved, current: current)

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

        #expect(result == ["A", "B", "C"])
    }

    @Test("produces no duplicates")
    func mergeNoDuplicates() {
        let saved = ["A", "B", "A", "C"]
        let current = ["A", "B", "C"]

        let result = OrderManager.merge(saved: saved, current: current)

        #expect(Set(result).count == result.count)
    }

    @Test("dedupes duplicates within current")
    func mergeDedupesCurrent() {
        let result = OrderManager.merge(saved: [], current: ["A", "B", "A", "C", "B"])
        #expect(result == ["A", "B", "C"])
    }

    // MARK: - File persistence (reconcile round-trips through disk)

    @Test("reconcile persists order and reloads it on the next call")
    func reconcilePersistsToDisk() {
        let path = NSTemporaryDirectory() + "aerospace-order-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let manager = OrderManager(orderFile: path)

        // First reconcile writes the order to disk (async on a serial queue).
        let first = manager.reconcile(with: ["A", "B", "C"])
        #expect(first == ["A", "B", "C"])

        // The next reconcile's load runs after the prior write on the same serial queue, so it
        // must observe the persisted order — appending D while preserving the saved arrangement.
        let second = manager.reconcile(with: ["A", "B", "C", "D"])
        #expect(second == ["A", "B", "C", "D"])

        // A workspace that no longer exists is dropped from the persisted order.
        let third = manager.reconcile(with: ["C", "B", "A"])
        #expect(third == ["A", "B", "C"])
    }

    @Test("reconcile writes valid JSON a fresh manager can read")
    func reconcileWritesReadableFile() {
        let path = NSTemporaryDirectory() + "aerospace-order-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let writer = OrderManager(orderFile: path)
        // Two reconciles on the same instance: the second's synchronous load acts as a barrier
        // guaranteeing the first write has flushed before we inspect the file.
        _ = writer.reconcile(with: ["X", "Y"])
        _ = writer.reconcile(with: ["X", "Y"])

        let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = data.flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        #expect(decoded == ["X", "Y"])
    }

    // MARK: - MockOrderProvider integration

    @Test("mock order provider mergeWithCurrent uses merge logic")
    func mockMergeWithCurrent() {
        let provider = MockOrderProvider()
        provider.savedOrder = ["C", "A"]

        let result = provider.mergeWithCurrent(["A", "B", "C"])

        #expect(result == ["C", "A", "B"])
    }

    @Test("mock order provider tracks save calls")
    func mockSaveTracking() {
        let provider = MockOrderProvider()

        provider.saveOrder(["A", "B"])
        provider.saveOrder(["A", "B", "C"])

        #expect(provider.saveCount == 2)
        #expect(provider.savedOrder == ["A", "B", "C"])
    }
}
