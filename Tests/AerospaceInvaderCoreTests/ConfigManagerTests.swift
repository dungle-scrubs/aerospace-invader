@testable import AerospaceInvaderCore
import Foundation
import Testing

@Suite("ConfigManager")
struct ConfigManagerTests {

    // MARK: - JSON parsing

    @Test("load config from valid JSON")
    func loadConfigFromValidJSON() {
        let jsonString = """
        {
            "back": { "key": "h", "modifiers": ["command"] },
            "forward": { "key": "l", "modifiers": ["command"] },
            "expand": { "key": "space", "modifiers": ["option"] },
            "toggle": { "key": "p", "modifiers": ["option"] }
        }
        """
        let json = Data(jsonString.utf8)

        let config = ConfigManager.loadConfig(from: json)

        #expect(config != nil)
        #expect(config?.back.key == "h")
        #expect(config?.back.modifiers == ["command"])
        #expect(config?.forward.key == "l")
        #expect(config?.expand.key == "space")
    }

    @Test("load config from invalid JSON")
    func loadConfigFromInvalidJSON() {
        let json = Data("not valid json".utf8)

        let config = ConfigManager.loadConfig(from: json)

        #expect(config == nil)
    }

    @Test("load config from partial JSON")
    func loadConfigFromPartialJSON() {
        // Missing required fields (forward, expand, toggle)
        let jsonString = """
        {
            "back": { "key": "h" }
        }
        """
        let json = Data(jsonString.utf8)

        let config = ConfigManager.loadConfig(from: json)

        #expect(config == nil)
    }

    @Test("load config with all modifiers")
    func loadConfigWithAllModifiers() {
        let jsonString = """
        {
            "back": { "key": "h", "modifiers": ["command", "shift", "option", "control"] },
            "forward": { "key": "l", "modifiers": ["command"] },
            "expand": { "key": "space", "modifiers": ["option"] },
            "toggle": { "key": "p", "modifiers": ["option"] }
        }
        """
        let json = Data(jsonString.utf8)

        let config = ConfigManager.loadConfig(from: json)

        #expect(config?.back.modifiers.count == 4)
    }

    // MARK: - Key code mapping

    @Test("keyCode returns correct code for lowercase letter")
    func keyCodeForLetter() {
        let code = ConfigManager.keyCode(for: "a")
        #expect(code != nil)
    }

    @Test("keyCode is case insensitive")
    func keyCodeCaseInsensitive() {
        let lower = ConfigManager.keyCode(for: "a")
        let upper = ConfigManager.keyCode(for: "A")
        #expect(lower == upper)
    }

    @Test("keyCode returns nil for unknown key")
    func keyCodeUnknownKey() {
        let code = ConfigManager.keyCode(for: "nonexistent")
        #expect(code == nil)
    }

    @Test("keyCode returns nil for empty string")
    func keyCodeEmptyString() {
        let code = ConfigManager.keyCode(for: "")
        #expect(code == nil)
    }

    @Test("keyCode works for special keys")
    func keyCodeSpecialKeys() {
        #expect(ConfigManager.keyCode(for: "space") != nil)
        #expect(ConfigManager.keyCode(for: "return") != nil)
        #expect(ConfigManager.keyCode(for: "tab") != nil)
        #expect(ConfigManager.keyCode(for: "escape") != nil)
        #expect(ConfigManager.keyCode(for: "delete") != nil)
        #expect(ConfigManager.keyCode(for: "left") != nil)
        #expect(ConfigManager.keyCode(for: "right") != nil)
        #expect(ConfigManager.keyCode(for: "up") != nil)
        #expect(ConfigManager.keyCode(for: "down") != nil)
    }

    @Test("keyCode works for punctuation")
    func keyCodePunctuation() {
        #expect(ConfigManager.keyCode(for: ".") != nil)
        #expect(ConfigManager.keyCode(for: ",") != nil)
        #expect(ConfigManager.keyCode(for: "/") != nil)
        #expect(ConfigManager.keyCode(for: ";") != nil)
        #expect(ConfigManager.keyCode(for: "-") != nil)
        #expect(ConfigManager.keyCode(for: "=") != nil)
    }

    @Test("keyCode works for digits")
    func keyCodeDigits() {
        for digit in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] {
            #expect(ConfigManager.keyCode(for: digit) != nil, "Missing key code for \(digit)")
        }
    }

    // MARK: - Modifier mask

    @Test("modifierMask combines multiple modifiers")
    func modifierMaskCombines() {
        let single = ConfigManager.modifierMask(for: ["option"])
        let double = ConfigManager.modifierMask(for: ["option", "shift"])
        #expect(double != single)
        #expect(double > single)
    }

    @Test("modifierMask handles aliases")
    func modifierMaskAliases() {
        #expect(ConfigManager.modifierMask(for: ["option"]) == ConfigManager.modifierMask(for: ["alt"]))
        #expect(ConfigManager.modifierMask(for: ["command"]) == ConfigManager.modifierMask(for: ["cmd"]))
        #expect(ConfigManager.modifierMask(for: ["control"]) == ConfigManager.modifierMask(for: ["ctrl"]))
    }

    @Test("modifierMask is case insensitive")
    func modifierMaskCaseInsensitive() {
        #expect(ConfigManager.modifierMask(for: ["Option"]) == ConfigManager.modifierMask(for: ["option"]))
        #expect(ConfigManager.modifierMask(for: ["COMMAND"]) == ConfigManager.modifierMask(for: ["command"]))
    }

    @Test("modifierMask ignores unknown modifiers")
    func modifierMaskUnknown() {
        let known = ConfigManager.modifierMask(for: ["option"])
        let withUnknown = ConfigManager.modifierMask(for: ["option", "nonexistent"])
        #expect(known == withUnknown)
    }

    @Test("modifierMask returns zero for empty array")
    func modifierMaskEmpty() {
        let mask = ConfigManager.modifierMask(for: [])
        #expect(mask == 0)
    }

    // MARK: - Hotkey description

    @Test("hotkeyDescription formats option modifier")
    func hotkeyDescOption() {
        let desc = ConfigManager.hotkeyDescription(HotkeyConfig(key: "o", modifiers: ["option"]))
        #expect(desc == "⌥O")
    }

    @Test("hotkeyDescription formats command modifier")
    func hotkeyDescCommand() {
        let desc = ConfigManager.hotkeyDescription(HotkeyConfig(key: "h", modifiers: ["command"]))
        #expect(desc == "⌘H")
    }

    @Test("hotkeyDescription formats multiple modifiers")
    func hotkeyDescMultiple() {
        let desc = ConfigManager.hotkeyDescription(HotkeyConfig(key: "x", modifiers: ["command", "shift"]))
        #expect(desc == "⌘⇧X")
    }

    @Test("hotkeyDescription formats alt alias")
    func hotkeyDescAlt() {
        let desc = ConfigManager.hotkeyDescription(HotkeyConfig(key: "i", modifiers: ["alt"]))
        #expect(desc == "⌥I")
    }

    // MARK: - Default config

    @Test("default config has expected keys")
    func defaultConfig() {
        let config = Config.default
        #expect(config.back.key == "o")
        #expect(config.forward.key == "i")
        #expect(config.expand.key == ".")
        #expect(config.toggle.key == "p")
    }

    @Test("default config uses option modifier")
    func defaultConfigModifiers() {
        let config = Config.default
        #expect(config.back.modifiers == ["option"])
        #expect(config.forward.modifiers == ["option"])
        #expect(config.expand.modifiers == ["option"])
        #expect(config.toggle.modifiers == ["option"])
    }

    @Test("config equality works")
    func configEquality() {
        let a = Config.default
        let b = Config.default
        #expect(a == b)

        let c = Config(
            back: HotkeyConfig(key: "h", modifiers: ["command"]),
            forward: HotkeyConfig(key: "l", modifiers: ["command"]),
            expand: HotkeyConfig(key: "space"),
            toggle: HotkeyConfig(key: "p")
        )
        #expect(a != c)
    }
}
