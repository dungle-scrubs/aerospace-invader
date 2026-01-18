import Carbon.HIToolbox
import Foundation

public class HotkeyManager {
    public static let shared = HotkeyManager()

    private var hotkeyRefs: [EventHotKeyRef?] = []
    public var onBack: (() -> Void)?
    public var onForward: (() -> Void)?
    public var onExpand: (() -> Void)?
    public var onToggle: (() -> Void)?

    private init() {}

    public func register() {
        let config = ConfigManager.shared.config

        // Install handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotkeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)

            DispatchQueue.main.async {
                switch hotkeyID.id {
                case 1: HotkeyManager.shared.onBack?()
                case 2: HotkeyManager.shared.onForward?()
                case 3: HotkeyManager.shared.onExpand?()
                case 4: HotkeyManager.shared.onToggle?()
                default: break
                }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)

        // Register hotkeys from config
        registerHotkey(config.back, id: 1)
        registerHotkey(config.forward, id: 2)
        registerHotkey(config.expand, id: 3)
        registerHotkey(config.toggle, id: 4)

        let backDesc = ConfigManager.hotkeyDescription(config.back)
        let forwardDesc = ConfigManager.hotkeyDescription(config.forward)
        let expandDesc = ConfigManager.hotkeyDescription(config.expand)
        let toggleDesc = ConfigManager.hotkeyDescription(config.toggle)
        fputs("Hotkeys registered: \(backDesc) (back), \(forwardDesc) (forward), \(expandDesc) (expand), \(toggleDesc) (toggle)\n", stderr)
    }

    private func registerHotkey(_ config: HotkeyConfig, id: UInt32) {
        guard let keyCode = ConfigManager.keyCode(for: config.key) else {
            fputs("Warning: Unknown key '\(config.key)' in config\n", stderr)
            return
        }
        let modifiers = ConfigManager.modifierMask(for: config.modifiers)
        let hotkeyID = EventHotKeyID(signature: OSType(0x4B565354), id: id)
        var hotkeyRef: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
        hotkeyRefs.append(hotkeyRef)
    }

    public func unregister() {
        for ref in hotkeyRefs {
            if let r = ref {
                UnregisterEventHotKey(r)
            }
        }
        hotkeyRefs.removeAll()
    }
}
