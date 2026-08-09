import Foundation

/// Deep adapter that owns aerospace binary discovery and trust validation — the one place
/// that decides whether a `$PATH`-resolved candidate is safe to execute. Previously this
/// logic lived inside `AerospaceAPI`, scattering security checks across the same file as
/// Process orchestration. Now the seam is explicit: `AerospaceAPI` asks the resolver for
/// a path, the resolver decides trust — and tests can inject a stub resolver without
/// touching the file system.
public final class BinaryResolver {
    private let armPath = "/opt/homebrew/bin/aerospace"
    private let intelPath = "/usr/local/bin/aerospace"

    private let pathLock = NSLock()
    private var _resolvedPath: String??

    public init() {}

    /// Resolved, cached path to the aerospace binary, or nil if not found / not trusted.
    public var path: String? {
        pathLock.lock()
        defer { pathLock.unlock() }
        if let cached = _resolvedPath { return cached }
        let resolved = discoverPath()
        _resolvedPath = .some(resolved)
        if let resolved = resolved {
            fputs("aerospace: using binary at \(resolved)\n", stderr)
        }
        return resolved
    }

    /// For tests — inject a known path and bypass discovery.
    public func setPathForTesting(_ path: String?) {
        pathLock.lock()
        _resolvedPath = .some(path)
        pathLock.unlock()
    }

    /// Reset the cache so the next `path` re-runs discovery (for tests that change `$PATH`).
    public func resetForTesting() {
        pathLock.lock()
        _resolvedPath = nil
        pathLock.unlock()
    }

    private func discoverPath() -> String? {
        if FileManager.default.fileExists(atPath: armPath) { return armPath }
        if FileManager.default.fileExists(atPath: intelPath) { return intelPath }
        return resolveFromPath()
    }

    private func resolveFromPath() -> String? {
        let pipe = Pipe()
        let task = ProcessRunner.makeProcess(executable: "/usr/bin/which", arguments: ["aerospace"], stdout: pipe)
        do {
            try task.run()
            task.waitUntilExit()
        } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = ProcessRunner.decodeOutput(data)
        guard !path.isEmpty, isTrustedExecutable(path) else {
            if !path.isEmpty {
                fputs("aerospace: refusing to use untrusted binary at \(path) (writable by group/other)\n", stderr)
            }
            return nil
        }
        return path
    }

    /// Validates that a `$PATH`-resolved candidate is safe to execute.
    func isTrustedExecutable(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return false }
        guard fm.isExecutableFile(atPath: path) else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        return !isWritableByOthers(path) && !isWritableByOthers(parent)
    }

    func isWritableByOthers(_ path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value
        else {
            return true
        }
        return (perms & 0o022) != 0
    }
}
