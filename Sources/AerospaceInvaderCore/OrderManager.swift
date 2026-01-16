import Foundation

public class OrderManager {
    public static let shared = OrderManager()
    private let configDir = NSHomeDirectory() + "/.config/aerospace-invader"
    private let orderFile: String

    private init() {
        orderFile = configDir + "/order.json"
        ensureConfigDir()
    }

    private func ensureConfigDir() {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
    }

    public func loadOrder() -> [String] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: orderFile)),
              let order = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return order
    }

    public func saveOrder(_ order: [String]) {
        guard let data = try? JSONEncoder().encode(order) else { return }
        try? data.write(to: URL(fileURLWithPath: orderFile))
    }

    /// Merge saved order with current non-empty workspaces.
    /// Preserves saved order for existing workspaces, appends new ones.
    public func mergeWithCurrent(_ current: [String]) -> [String] {
        let saved = loadOrder()
        return OrderManager.merge(saved: saved, current: current)
    }

    /// Pure function for merging - testable without file I/O
    public static func merge(saved: [String], current: [String]) -> [String] {
        let currentSet = Set(current)
        var seen = Set<String>()
        var result: [String] = []

        // Keep saved items that still exist (deduplicated, preserving first occurrence)
        for ws in saved {
            if currentSet.contains(ws) && !seen.contains(ws) {
                result.append(ws)
                seen.insert(ws)
            }
        }

        // Append new workspaces not in saved order
        for ws in current where !seen.contains(ws) {
            result.append(ws)
            seen.insert(ws)
        }

        return result
    }
}
