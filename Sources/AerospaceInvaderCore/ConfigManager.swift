import Carbon.HIToolbox
import Foundation

public struct HotkeyConfig: Codable, Equatable {
    public var key: String
    public var modifiers: [String]

    public init(key: String, modifiers: [String] = ["option"]) {
        self.key = key
        self.modifiers = modifiers
    }
}

public struct Config: Codable, Equatable {
    public var back: HotkeyConfig
    public var forward: HotkeyConfig
    public var expand: HotkeyConfig
    public var refresh: HotkeyConfig

    public static let `default` = Config(
        back: HotkeyConfig(key: "o"),
        forward: HotkeyConfig(key: "i"),
        expand: HotkeyConfig(key: "."),
        refresh: HotkeyConfig(key: "p")
    )

    public init(back: HotkeyConfig, forward: HotkeyConfig, expand: HotkeyConfig, refresh: HotkeyConfig) {
        self.back = back
        self.forward = forward
        self.expand = expand
        self.refresh = refresh
    }
}

public class ConfigManager {
    public static let shared = ConfigManager()
    private let configDir = NSHomeDirectory() + "/.config/aerospace-invader"
    private let configFile: String
    public private(set) var config: Config

    private init() {
        configFile = configDir + "/config.json"
        config = Config.default
        ensureConfigDir()
        config = ConfigManager.loadConfig(from: configFile) ?? Config.default
    }

    private func ensureConfigDir() {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
    }

    public static func loadConfig(from path: String) -> Config? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(Config.self, from: data)
    }

    public static func loadConfig(from data: Data) -> Config? {
        let decoder = JSONDecoder()
        return try? decoder.decode(Config.self, from: data)
    }

    public func saveDefaultConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Config.default) else { return }
        try? data.write(to: URL(fileURLWithPath: configFile))
        fputs("Default config written to: \(configFile)\n", stderr)
    }

    // Key name to Carbon key code
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

    // Modifier name to Carbon modifier mask
    public static let modifierMasks: [String: Int] = [
        "option": optionKey,
        "alt": optionKey,
        "command": cmdKey,
        "cmd": cmdKey,
        "control": controlKey,
        "ctrl": controlKey,
        "shift": shiftKey
    ]

    public static func keyCode(for key: String) -> UInt32? {
        guard let code = keyCodes[key.lowercased()] else { return nil }
        return UInt32(code)
    }

    public static func modifierMask(for modifiers: [String]) -> UInt32 {
        var mask = 0
        for mod in modifiers {
            if let m = modifierMasks[mod.lowercased()] {
                mask |= m
            }
        }
        return UInt32(mask)
    }

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
