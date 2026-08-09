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

    /// Decodes a binding, defaulting `modifiers` to `["option"]` when omitted so a config that
    /// specifies only a key still parses.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        modifiers = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? ["option"]
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

    /// Decodes a config, filling any omitted binding from `Config.default`. This keeps a
    /// forward-compatible or partial config file from resetting every unrelated binding.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Config.default
        back = try container.decodeIfPresent(HotkeyConfig.self, forKey: .back) ?? fallback.back
        forward = try container.decodeIfPresent(HotkeyConfig.self, forKey: .forward) ?? fallback.forward
        expand = try container.decodeIfPresent(HotkeyConfig.self, forKey: .expand) ?? fallback.expand
        toggle = try container.decodeIfPresent(HotkeyConfig.self, forKey: .toggle) ?? fallback.toggle
    }
}

/// Manages loading and persisting hotkey configuration.
/// Now a thin adapter over `PersistedState` for the file seam and `KeyLexicon` for the
/// key-display seam — the deep modules that concentrate the real logic.
public final class ConfigManager: ConfigurationProvider {
    /// Shared singleton for production use.
    public static let shared = ConfigManager()

    private let persisted: PersistedState
    private let queue = DispatchQueue(label: "com.aerospace-invader.config")
    private var _config: Config

    /// The current hotkey configuration (thread-safe read).
    public var config: Config {
        queue.sync { _config }
    }

    private init(persisted: PersistedState = .shared) {
        self.persisted = persisted
        _config = persisted.loadConfig() ?? Config.default
    }

    /// Test initializer that injects a custom persisted state (e.g. temp directory).
    init(persisted: PersistedState, initial: Config = .default) {
        self.persisted = persisted
        self._config = initial
        if let loaded = persisted.loadConfig() { _config = loaded }
    }

    /// Loads a `Config` from a file path. Preserved for tests that use path-based loading.
    public static func loadConfig(from path: String) -> Config? {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            if !ConfigStore.isFileNotFound(error) {
                fputs("ConfigManager: failed to load config from \(path) — \(error.localizedDescription)\n", stderr)
            }
            return nil
        }
    }

    /// Loads a `Config` from raw JSON data (for testing).
    public static func loadConfig(from data: Data) -> Config? {
        try? JSONDecoder().decode(Config.self, from: data)
    }

    // MARK: - Key Code Mapping — single source is KeyLexicon

    /// Maps lowercase key names to Carbon virtual key codes. Forwards to `KeyLexicon`.
    public static let keyCodes: [String: Int] = KeyLexicon.keyCodes

    /// Converts a key name to its Carbon virtual key code. Forwards to `KeyLexicon`.
    public static func keyCode(for key: String) -> UInt32? {
        KeyLexicon.keyCode(for: key)
    }

    /// Combines modifier names into a single Carbon modifier mask. Forwards to `KeyLexicon`.
    public static func modifierMask(for modifiers: [String]) -> UInt32 {
        KeyLexicon.modifierMask(for: modifiers)
    }

    /// Formats a hotkey config as a human-readable string. Forwards to `KeyLexicon`.
    public static func hotkeyDescription(_ config: HotkeyConfig) -> String {
        KeyLexicon.hotkeyDescription(config)
    }
}
