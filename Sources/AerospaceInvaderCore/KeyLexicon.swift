import Carbon.HIToolbox
import Foundation

/// Single source of truth for key names, modifier glyphs, Carbon key codes, and display
/// formatting. Previously this knowledge was split across `ConfigManager.keyCodes`,
/// `Modifier`, and `BindingFormatter.specialKeys` — three places that drifted.
/// Now one module owns every mapping from raw `aerospace.toml` strings to glyphs and masks.
///
/// Depth: one interface behind which all key-display logic concentrates; both hotkey
/// registration and which-key formatting call into the same lexicon.
public enum KeyLexicon {
    // MARK: - Modifier

    /// All modifiers known to the system, centralized so `alt → ⌥` is defined once.
    public static func modifier(for name: String) -> Modifier? {
        Modifier(name: name)
    }

    // MARK: - Key codes

    /// Maps lowercase key names to Carbon virtual key codes. Single source for hotkey registration.
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

    /// Converts a key name to its Carbon virtual key code.
    public static func keyCode(for key: String) -> UInt32? {
        guard let code = keyCodes[key.lowercased()] else { return nil }
        return UInt32(code)
    }

    /// Combines modifier names into a single Carbon modifier mask.
    public static func modifierMask(for modifiers: [String]) -> UInt32 {
        let mask = modifiers.reduce(0) { $0 | (Modifier(name: $1)?.mask ?? 0) }
        return UInt32(mask)
    }

    // MARK: - Display

    /// Special non-modifier key names that render as a symbol in the OSD.
    public static let specialKeySymbols: [String: String] = [
        "backspace": "⌫",
        "esc": "Esc",
        "semicolon": ";",
        "comma": ",",
        "slash": "/"
    ]

    /// Formats a raw AeroSpace key string (e.g. `alt-shift-h`) to readable symbols (`⌥⇧H`).
    /// Delegates to Modifier for glyphs so the app has one modifier table.
    public static func formatKey(_ key: String) -> String {
        let tokens = key.split(separator: "-").map(String.init)
        guard let last = tokens.last else { return key }
        let modifiers = tokens.dropLast().compactMap { Modifier(name: $0)?.symbol }.joined()
        let keyPart = specialKeySymbols[last] ?? last
        return modifiers + keyPart
    }

    /// Formats a hotkey config as a human-readable string (e.g. "⌥O").
    public static func hotkeyDescription(_ config: HotkeyConfig) -> String {
        let symbols = config.modifiers.compactMap { Modifier(name: $0)?.symbol }
        return (symbols + [config.key.uppercased()]).joined()
    }
}

/// A keyboard modifier, owning the single source of truth for its name aliases,
/// Carbon mask, and display glyph. Moved out of ConfigManager so BindingFormatter
/// and ConfigManager share the same table.
public enum Modifier {
    case option, command, control, shift

    /// Resolves a modifier name (case-insensitive, including aliases like "alt"/"cmd"/"ctrl").
    public init?(name: String) {
        switch name.lowercased() {
        case "option", "alt": self = .option
        case "command", "cmd": self = .command
        case "control", "ctrl": self = .control
        case "shift": self = .shift
        default: return nil
        }
    }

    /// Carbon modifier mask.
    public var mask: Int {
        switch self {
        case .option: return optionKey
        case .command: return cmdKey
        case .control: return controlKey
        case .shift: return shiftKey
        }
    }

    /// Display glyph for the modifier.
    public var symbol: String {
        switch self {
        case .option: return "⌥"
        case .command: return "⌘"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }
}
