import Foundation

/// Shared on-disk location and helpers for the app's config and state files.
enum ConfigStore {
    /// Directory holding all aerospace-invader config and state files.
    static let directory = NSHomeDirectory() + "/.config/aerospace-invader"

    /// Creates the config directory if needed, logging failures tagged with `context`.
    static func ensureDirectory(context: String) {
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
