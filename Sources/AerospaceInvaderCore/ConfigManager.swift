import Carbon.HIToolbox
import Foundation

/// A single hotkey binding — key name + modifier keys.
public struct HotkeyConfig: Codable, Equatable {
    public var key: String
    public var modifiers: [String]

    /// Creates a hotkey configuration.
    /// - Parameters:
    ///   - key: The key name (e.g. "o", "i", ".", "space").
    ///   - modifiers: Modifier key names (e.g. ["option"], ["command", "shift"]).
    public init(key: String, modifiers: [String] = ["option"]) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// Top-level configuration with all four hotkey bindings.
public struct Config: Codable, Equatable {
    public var back: HotkeyConfig
    public var forward: HotkeyConfig
    public var expand: HotkeyConfig
    public var toggle: HotkeyConfig

    /// Default configuration: ⌥O back, ⌥I forward, ⌥. expand, ⌥P toggle.
    public static let `default` = Config(
        back: HotkeyConfig(key: "o"),
        forward: HotkeyConfig(key: "i"),
        expand: HotkeyConfig(key: "."),
        toggle: HotkeyConfig(key: "p")
    )

    public init(back: HotkeyConfig, forward: HotkeyConfig, expand: HotkeyConfig, toggle: HotkeyConfig) {
        self.back = back
        self.forward = forward
        self.expand = expand
        self.toggle = toggle
    }
}

/// Manages loading and persisting hotkey configuration from `~/.config/aerospace-invader/config.json`.
/// Thread-safe via a serial dispatch queue.
public class ConfigManager: ConfigurationProvider {
    /// Shared singleton for production use.
    public static let shared = ConfigManager()

    private let queue = DispatchQueue(label: "com.aerospace-invader.config")
    private let configDir = NSHomeDirectory() + "/.config/aerospace-invader"
    private let configFile: String
    private var _config: Config

    /// The current hotkey configuration (thread-safe read).
    public var config: Config {
        queue.sync { _config }
    }

    private init() {
        configFile = configDir + "/config.json"
        _config = Config.default
        ensureConfigDir()
        _config = ConfigManager.loadConfig(from: configFile) ?? Config.default
    }

    private func ensureConfigDir() {
        do {
            try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        } catch {
            fputs("ConfigManager: failed to create config dir — \(error.localizedDescription)\n", stderr)
        }
    }

    /// Loads a `Config` from a file path.
    /// - Parameter path: Absolute path to a JSON config file.
    /// - Returns: Parsed config, or nil if the file doesn't exist or is malformed.
    public static func loadConfig(from path: String) -> Config? {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            if (error as NSError).domain != NSCocoaErrorDomain || (error as NSError).code != NSFileReadNoSuchFileError {
                fputs("ConfigManager: failed to load config from \(path) — \(error.localizedDescription)\n", stderr)
            }
            return nil
        }
    }

    /// Loads a `Config` from raw JSON data (for testing).
    /// - Parameter data: JSON-encoded config data.
    /// - Returns: Parsed config, or nil if invalid.
    public static func loadConfig(from data: Data) -> Config? {
        try? JSONDecoder().decode(Config.self, from: data)
    }

    // MARK: - Key Code Mapping

    /// Maps lowercase key names to Carbon virtual key codes.
    public static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        ".": kVK_ANSI_Period, ",": kVK_ANSI_Comma, "/": kVK_ANSI_Slash,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "[": kVK_ANSI_LeftBracket,
        "]": kVK_ANSI_RightBracket, "\\": kVK_ANSI_Backslash, "-": kVK_ANSI_Minus,
        "=": kVK_ANSI_Equal, "`": kVK_ANSI_Grave,
        "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab,
        "escape": kVK_Escape, "delete": kVK_Delete,
        "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "up": kVK_UpArrow, "down": kVK_DownArrow
    ]

    /// Maps modifier names (case-insensitive) to Carbon modifier masks.
    public static let modifierMasks: [String: Int] = [
        "option": optionKey,
        "alt": optionKey,
        "command": cmdKey,
        "cmd": cmdKey,
        "control": controlKey,
        "ctrl": controlKey,
        "shift": shiftKey
    ]

    /// Converts a key name to its Carbon virtual key code.
    /// - Parameter key: Key name (case-insensitive).
    /// - Returns: Key code, or nil for unknown keys.
    public static func keyCode(for key: String) -> UInt32? {
        guard let code = keyCodes[key.lowercased()] else { return nil }
        return UInt32(code)
    }

    /// Combines modifier names into a single Carbon modifier mask.
    /// - Parameter modifiers: Array of modifier names (case-insensitive).
    /// - Returns: Combined modifier mask. Unknown modifiers are ignored.
    public static func modifierMask(for modifiers: [String]) -> UInt32 {
        var mask = 0
        for mod in modifiers {
            if let m = modifierMasks[mod.lowercased()] {
                mask |= m
            }
        }
        return UInt32(mask)
    }

    /// Formats a hotkey config as a human-readable string (e.g. "⌥O").
    /// - Parameter config: The hotkey configuration.
    /// - Returns: String with modifier symbols followed by the key.
    public static func hotkeyDescription(_ config: HotkeyConfig) -> String {
        var parts: [String] = []
        for mod in config.modifiers {
            switch mod.lowercased() {
            case "option", "alt": parts.append("⌥")
            case "command", "cmd": parts.append("⌘")
            case "control", "ctrl": parts.append("⌃")
            case "shift": parts.append("⇧")
            default: break
            }
        }
        parts.append(config.key.uppercased())
        return parts.joined()
    }
}
