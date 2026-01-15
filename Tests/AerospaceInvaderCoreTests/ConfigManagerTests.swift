import Testing
@testable import AerospaceInvaderCore

@Suite("ConfigManager")
struct ConfigManagerTests {

    // MARK: - keyCode(for:) tests

    @Test("key code for letter")
    func keyCodeForLetter() {
        #expect(ConfigManager.keyCode(for: "a") != nil)
        #expect(ConfigManager.keyCode(for: "z") != nil)
        #expect(ConfigManager.keyCode(for: "A") != nil)  // Case insensitive
        #expect(ConfigManager.keyCode(for: "Z") != nil)
    }

    @Test("key code for number")
    func keyCodeForNumber() {
        #expect(ConfigManager.keyCode(for: "0") != nil)
        #expect(ConfigManager.keyCode(for: "9") != nil)
    }

    @Test("key code for symbol")
    func keyCodeForSymbol() {
        #expect(ConfigManager.keyCode(for: ".") != nil)
        #expect(ConfigManager.keyCode(for: ",") != nil)
        #expect(ConfigManager.keyCode(for: "/") != nil)
        #expect(ConfigManager.keyCode(for: "-") != nil)
    }

    @Test("key code for special keys")
    func keyCodeForSpecialKeys() {
        #expect(ConfigManager.keyCode(for: "space") != nil)
        #expect(ConfigManager.keyCode(for: "return") != nil)
        #expect(ConfigManager.keyCode(for: "tab") != nil)
        #expect(ConfigManager.keyCode(for: "escape") != nil)
    }

    @Test("key code for arrows")
    func keyCodeForArrows() {
        #expect(ConfigManager.keyCode(for: "left") != nil)
        #expect(ConfigManager.keyCode(for: "right") != nil)
        #expect(ConfigManager.keyCode(for: "up") != nil)
        #expect(ConfigManager.keyCode(for: "down") != nil)
    }

    @Test("key code for unknown returns nil")
    func keyCodeForUnknown() {
        #expect(ConfigManager.keyCode(for: "invalid") == nil)
        #expect(ConfigManager.keyCode(for: "") == nil)
        #expect(ConfigManager.keyCode(for: "f1") == nil)  // Function keys not in list
    }

    // MARK: - modifierMask(for:) tests

    @Test("modifier mask single")
    func modifierMaskSingle() {
        let optionMask = ConfigManager.modifierMask(for: ["option"])
        #expect(optionMask != 0)

        let altMask = ConfigManager.modifierMask(for: ["alt"])
        #expect(optionMask == altMask)  // Aliases should match

        let cmdMask = ConfigManager.modifierMask(for: ["command"])
        #expect(cmdMask != 0)
        #expect(cmdMask != optionMask)
    }

    @Test("modifier mask multiple")
    func modifierMaskMultiple() {
        let combined = ConfigManager.modifierMask(for: ["option", "command"])
        let option = ConfigManager.modifierMask(for: ["option"])
        let command = ConfigManager.modifierMask(for: ["command"])

        // Combined should include both
        #expect(combined == option | command)
    }

    @Test("modifier mask empty")
    func modifierMaskEmpty() {
        let mask = ConfigManager.modifierMask(for: [])
        #expect(mask == 0)
    }

    @Test("modifier mask unknown")
    func modifierMaskUnknown() {
        let mask = ConfigManager.modifierMask(for: ["invalid"])
        #expect(mask == 0)
    }

    @Test("modifier mask case insensitive")
    func modifierMaskCaseInsensitive() {
        let lower = ConfigManager.modifierMask(for: ["option"])
        let upper = ConfigManager.modifierMask(for: ["OPTION"])
        let mixed = ConfigManager.modifierMask(for: ["Option"])

        #expect(lower == upper)
        #expect(lower == mixed)
    }

    // MARK: - hotkeyDescription tests

    @Test("hotkey description option")
    func hotkeyDescriptionOption() {
        let config = HotkeyConfig(key: "o", modifiers: ["option"])
        let desc = ConfigManager.hotkeyDescription(config)

        #expect(desc == "⌥O")
    }

    @Test("hotkey description multiple modifiers")
    func hotkeyDescriptionMultipleModifiers() {
        let config = HotkeyConfig(key: "x", modifiers: ["command", "shift"])
        let desc = ConfigManager.hotkeyDescription(config)

        #expect(desc.contains("⌘"))
        #expect(desc.contains("⇧"))
        #expect(desc.contains("X"))
    }

    @Test("hotkey description alt alias")
    func hotkeyDescriptionAltAlias() {
        let optConfig = HotkeyConfig(key: "a", modifiers: ["option"])
        let altConfig = HotkeyConfig(key: "a", modifiers: ["alt"])

        #expect(ConfigManager.hotkeyDescription(optConfig) == ConfigManager.hotkeyDescription(altConfig))
    }

    // MARK: - loadConfig tests

    @Test("load config from valid JSON")
    func loadConfigFromValidJSON() {
        let json = """
        {
            "back": { "key": "h", "modifiers": ["command"] },
            "forward": { "key": "l", "modifiers": ["command"] },
            "expand": { "key": "space", "modifiers": ["option"] }
        }
        """.data(using: .utf8)!

        let config = ConfigManager.loadConfig(from: json)

        #expect(config != nil)
        #expect(config?.back.key == "h")
        #expect(config?.back.modifiers == ["command"])
        #expect(config?.forward.key == "l")
        #expect(config?.expand.key == "space")
    }

    @Test("load config from invalid JSON")
    func loadConfigFromInvalidJSON() {
        let json = "not valid json".data(using: .utf8)!

        let config = ConfigManager.loadConfig(from: json)

        #expect(config == nil)
    }

    @Test("load config from partial JSON")
    func loadConfigFromPartialJSON() {
        // Missing required field
        let json = """
        {
            "back": { "key": "h" }
        }
        """.data(using: .utf8)!

        let config = ConfigManager.loadConfig(from: json)

        #expect(config == nil)  // Should fail because forward/expand are missing
    }

    // MARK: - Default config tests

    @Test("default config")
    func defaultConfig() {
        let config = Config.default

        #expect(config.back.key == "o")
        #expect(config.back.modifiers == ["option"])
        #expect(config.forward.key == "i")
        #expect(config.expand.key == ".")
    }

    @Test("hotkey config equatable")
    func hotkeyConfigEquatable() {
        let a = HotkeyConfig(key: "a", modifiers: ["option"])
        let b = HotkeyConfig(key: "a", modifiers: ["option"])
        let c = HotkeyConfig(key: "b", modifiers: ["option"])

        #expect(a == b)
        #expect(a != c)
    }
}
