import Foundation

public class AerospaceAPI {
    public static let aerospacePath: String = {
        // Apple Silicon (Homebrew)
        let armPath = "/opt/homebrew/bin/aerospace"
        // Intel Mac (Homebrew)
        let intelPath = "/usr/local/bin/aerospace"

        if FileManager.default.fileExists(atPath: armPath) {
            return armPath
        } else if FileManager.default.fileExists(atPath: intelPath) {
            return intelPath
        }
        // Fallback - hope it's in PATH (won't work with full path but process will fail gracefully)
        return armPath
    }()

    /// Check if aerospace is enabled by trying to list workspaces.
    /// If it fails, enable aerospace.
    public static func ensureEnabled() -> Bool {
        // Try a simple command to check if aerospace is responding
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: aerospacePath)
        checkTask.arguments = ["list-workspaces", "--focused"]

        let pipe = Pipe()
        checkTask.standardOutput = pipe
        checkTask.standardError = FileHandle.nullDevice

        do {
            try checkTask.run()
            checkTask.waitUntilExit()
        } catch {
            // Aerospace not running at all, try to enable
            return enableAerospace()
        }

        // If exit code is non-zero or no output, try enabling
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if checkTask.terminationStatus == 0 && !output.isEmpty {
            return true
        }

        return enableAerospace()
    }

    private static func enableAerospace() -> Bool {
        fputs("Aerospace not responding, enabling...\n", stderr)
        let enableTask = Process()
        enableTask.executableURL = URL(fileURLWithPath: aerospacePath)
        enableTask.arguments = ["enable", "on"]
        enableTask.standardOutput = FileHandle.nullDevice
        enableTask.standardError = FileHandle.nullDevice

        do {
            try enableTask.run()
            enableTask.waitUntilExit()
            // Give it a moment to initialize
            Thread.sleep(forTimeInterval: 0.5)
            return true
        } catch {
            fputs("Failed to enable aerospace\n", stderr)
            return false
        }
    }

    public static func getNonEmptyWorkspaces() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: aerospacePath)
        task.arguments = ["list-workspaces", "--monitor", "all", "--empty", "no"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func getCurrentWorkspace() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: aerospacePath)
        task.arguments = ["list-workspaces", "--focused"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func switchToWorkspace(_ ws: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: aerospacePath)
        task.arguments = ["workspace", ws]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    public static func getBindings(mode: String) -> [String: String]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: aerospacePath)
        task.arguments = ["config", "--get", "mode.\(mode).binding", "--json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }
}
