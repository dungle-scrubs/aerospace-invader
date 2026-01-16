import Testing
@testable import AerospaceInvaderCore

@Suite("ConfigManager")
struct ConfigManagerTests {

    @Test("load config from valid JSON")
    func loadConfigFromValidJSON() {
        let json = """
        {
            "back": { "key": "h", "modifiers": ["command"] },
            "forward": { "key": "l", "modifiers": ["command"] },
            "expand": { "key": "space", "modifiers": ["option"] },
            "refresh": { "key": "p", "modifiers": ["option"] }
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
        let json = """
        {
            "back": { "key": "h" }
        }
        """.data(using: .utf8)!

        let config = ConfigManager.loadConfig(from: json)

        #expect(config == nil)
    }
}
