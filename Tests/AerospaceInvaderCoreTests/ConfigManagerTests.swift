@testable import AerospaceInvaderCore
import Foundation
import Testing

@Suite("ConfigManager")
struct ConfigManagerTests {

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
        let jsonString = """
        {
            "back": { "key": "h" }
        }
        """
        let json = Data(jsonString.utf8)

        let config = ConfigManager.loadConfig(from: json)

        #expect(config == nil)
    }
}
