import Foundation

/// Deep module that owns all on-disk persistence — one queue, one directory, one
/// failure model, atomic writes. Previously ConfigManager and OrderManager each owned
/// their own serial queue, duplicated `ensureDirectory` + `isFileNotFound` handling,
/// and raced `reconcile`'s sync load against an async save. Now they share a single
/// seam, and adding a persisted preference is one property instead of a new manager.
///
/// The module is deliberately small in interface (load/save/reconcile) and large in
/// implementation (directory creation, atomic write, error swallowing for first-run).
public final class PersistedState {
    /// Shared singleton for production use. Tests inject a temp directory via the
    /// `directory` initializer.
    public static let shared = PersistedState()

    private let queue: DispatchQueue
    private let directory: String
    private let configFile: String
    private let orderFile: String

    // MARK: - Initialization

    /// Production initializer — mirrors the former ConfigStore/ConfigManager/OrderManager
    /// directory (`~/.config/aerospace-invader`) and labels the queue for the combined module.
    private init() {
        self.directory = NSHomeDirectory() + "/.config/aerospace-invader"
        self.configFile = directory + "/config.json"
        self.orderFile = directory + "/order.json"
        self.queue = DispatchQueue(label: "com.aerospace-invader.persisted")
        ensureDirectory(context: "PersistedState")
    }

    /// Test initializer — inject any directory so tests never touch the real home.
    public init(directory: String) {
        self.directory = directory
        self.configFile = directory + "/config.json"
        self.orderFile = directory + "/order.json"
        self.queue = DispatchQueue(label: "com.aerospace-invader.persisted.\(UUID().uuidString)")
        ensureDirectory(context: "PersistedState")
    }

    /// Test initializer — inject an explicit order file path (mirrors OrderManager(orderFile:)).
    public init(orderFile: String) {
        let dir = (orderFile as NSString).deletingLastPathComponent
        self.directory = dir
        self.configFile = dir + "/config.json"
        self.orderFile = orderFile
        self.queue = DispatchQueue(label: "com.aerospace-invader.persisted.\(UUID().uuidString)")
        ensureDirectory(context: "PersistedState")
    }

    // MARK: - Directory

    private func ensureDirectory(context: String) {
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            fputs("\(context): failed to create config dir — \(error.localizedDescription)\n", stderr)
        }
    }

    private static func isFileNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError
    }

    // MARK: - Config

    /// Load a Config from disk, or nil if missing/malformed.
    public func loadConfig() -> Config? {
        queue.sync {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: configFile))
                return try JSONDecoder().decode(Config.self, from: data)
            } catch {
                if !Self.isFileNotFound(error) {
                    fputs("PersistedState: failed to load config — \(error.localizedDescription)\n", stderr)
                }
                return nil
            }
        }
    }

    /// Save a Config atomically.
    public func saveConfig(_ config: Config) {
        queue.async(flags: .barrier) {
            do {
                let data = try JSONEncoder().encode(config)
                try data.write(to: URL(fileURLWithPath: self.configFile), options: .atomic)
            } catch {
                fputs("PersistedState: failed to save config — \(error.localizedDescription)\n", stderr)
            }
        }
    }

    // MARK: - Order

    /// Load the persisted workspace order (thread-safe, sync).
    public func loadOrder() -> [String] {
        queue.sync {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: orderFile))
                return try JSONDecoder().decode([String].self, from: data)
            } catch {
                if !Self.isFileNotFound(error) {
                    fputs("PersistedState: failed to load order — \(error.localizedDescription)\n", stderr)
                }
                return []
            }
        }
    }

    /// Save a workspace order atomically with a barrier, so a subsequent load on the same
    /// queue is guaranteed to observe the write (fixes the former async-without-barrier race
    /// where `reconcile` could return before the write landed).
    public func saveOrder(_ order: [String]) {
        queue.async(flags: .barrier) {
            do {
                let data = try JSONEncoder().encode(order)
                try data.write(to: URL(fileURLWithPath: self.orderFile), options: .atomic)
            } catch {
                fputs("PersistedState: failed to save order — \(error.localizedDescription)\n", stderr)
            }
        }
    }

    /// Reconcile saved order with current workspaces, persist the result, and return it.
    /// Uses the same queue barrier as `saveOrder`, so callers that immediately re-load
    /// observe the persisted result (the former load used `sync` on a different queue instance
    /// and could miss the async write).
    public func reconcile(with current: [String]) -> [String] {
        // loadOrder already syncs; compute merge outside queue to avoid re-entrance deadlock,
        // but hold barrier for the write so the returned value is durable for the next call.
        let saved = loadOrder()
        let merged = Self.merge(saved: saved, current: current)
        saveOrder(merged)
        return merged
    }

    /// Pure merge — testable without file I/O. Keeps saved ordering, deduplicates, appends new.
    public static func merge(saved: [String], current: [String]) -> [String] {
        let currentSet = Set(current)
        var seen = Set<String>()
        var result: [String] = []
        for ws in saved where currentSet.contains(ws) && !seen.contains(ws) {
            result.append(ws); seen.insert(ws)
        }
        for ws in current where !seen.contains(ws) {
            result.append(ws); seen.insert(ws)
        }
        return result
    }

    // MARK: - File paths exposed for backward compatibility

    /// Absolute paths, matching the former ConfigStore values.
    public var configFilePath: String { configFile }
    public var orderFilePath: String { orderFile }
    public var directoryPath: String { directory }
}
