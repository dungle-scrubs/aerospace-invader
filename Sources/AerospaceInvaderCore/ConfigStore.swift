import Foundation

/// Shared on-disk location and helpers for the app's config and state files.
/// Now a thin compatibility shim over `PersistedState` — the deep module that owns the
/// directory, file paths, and failure model. Callers should prefer `PersistedState.shared`.
public enum ConfigStore {
    /// Directory holding all aerospace-invader config and state files.
    public static var directory: String { PersistedState.shared.directoryPath }
    /// Absolute path to the hotkey configuration file.
    public static var configFile: String { PersistedState.shared.configFilePath }
    /// Absolute path to the persisted workspace-order file.
    public static var orderFile: String { PersistedState.shared.orderFilePath }

    /// Creates the config directory if needed, logging failures tagged with `context`.
    /// Forwards to `PersistedState` so directory creation has one owner.
    static func ensureDirectory(context: String) {
        // PersistedState creates the directory on init; this no-ops if it already exists.
        _ = PersistedState.shared
        // Keep the legacy fputs contract: if creation ever fails, PersistedState already logged.
        // This shim preserves the call site for existing error-context strings without duplicating logic.
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            fputs("\(context): failed to create config dir — \(error.localizedDescription)\n", stderr)
        }
    }

    /// True when `error` is the Cocoa "file does not exist" error, which is expected on first run.
    static func isFileNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError
    }
}
