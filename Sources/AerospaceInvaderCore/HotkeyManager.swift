import Carbon.HIToolbox
import Foundation

/// Registers global hotkeys via Carbon Event APIs and dispatches callbacks on the main thread.
/// Uses debouncing to prevent rapid-fire navigation from concurrent key presses.
public class HotkeyManager {
    /// Identifies which navigation action a registered hotkey triggers, and owns
    /// each action's id, log label, and which `Config` binding drives it.
    private enum HotkeyAction: UInt32, CaseIterable {
        case back = 1, forward = 2, expand = 3, toggle = 4

        /// Human-readable role, used in the registration log line.
        var label: String {
            switch self {
            case .back: return "back"
            case .forward: return "forward"
            case .expand: return "expand"
            case .toggle: return "toggle"
            }
        }

        /// The configured binding for this action.
        func binding(in config: Config) -> HotkeyConfig {
            switch self {
            case .back: return config.back
            case .forward: return config.forward
            case .expand: return config.expand
            case .toggle: return config.toggle
            }
        }
    }

    /// Shared singleton for production use.
    public static let shared = HotkeyManager()

    private var hotkeyRefs: [EventHotKeyRef?] = []

    /// Callback for the "back" hotkey.
    public var onBack: (() -> Void)?
    /// Callback for the "forward" hotkey.
    public var onForward: (() -> Void)?
    /// Callback for the "expand" hotkey.
    public var onExpand: (() -> Void)?
    /// Callback for the "toggle" hotkey.
    public var onToggle: (() -> Void)?

    /// Minimum interval between hotkey dispatches (prevents rapid-fire navigation).
    private let debounceInterval: TimeInterval = 0.08
    /// Timestamp of the last dispatched hotkey callback.
    private var lastDispatchTime: TimeInterval = 0

    private let configProvider: ConfigurationProvider

    /// Creates a hotkey manager.
    /// - Parameter configProvider: Source of hotkey configuration (default: `ConfigManager.shared`).
    public init(configProvider: ConfigurationProvider = ConfigManager.shared) {
        self.configProvider = configProvider
    }

    /// Registers all hotkeys from the current configuration and installs the event handler.
    public func register() {
        let config = configProvider.config

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotkeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)

            let now = ProcessInfo.processInfo.systemUptime
            let manager = HotkeyManager.shared

            // Debounce: skip if fired too recently
            guard now - manager.lastDispatchTime >= manager.debounceInterval else {
                return noErr
            }
            manager.lastDispatchTime = now

            DispatchQueue.main.async {
                guard let action = HotkeyAction(rawValue: hotkeyID.id) else { return }
                manager.dispatch(action)
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)

        for action in HotkeyAction.allCases {
            registerHotkey(action.binding(in: config), id: action.rawValue)
        }

        let summary = HotkeyAction.allCases
            .map { "\(ConfigManager.hotkeyDescription($0.binding(in: config))) (\($0.label))" }
            .joined(separator: ", ")
        fputs("Hotkeys registered: \(summary)\n", stderr)

        // Install signal handlers for cleanup on SIGTERM/SIGINT
        installSignalHandlers()
    }

    /// Invokes the callback bound to a hotkey action (read live, so reassignment takes effect).
    private func dispatch(_ action: HotkeyAction) {
        switch action {
        case .back: onBack?()
        case .forward: onForward?()
        case .expand: onExpand?()
        case .toggle: onToggle?()
        }
    }

    /// Registers a single hotkey with the Carbon event system.
    /// - Parameters:
    ///   - config: The hotkey configuration (key + modifiers).
    ///   - id: Numeric identifier for the hotkey (1-4).
    private func registerHotkey(_ config: HotkeyConfig, id: UInt32) {
        guard let keyCode = ConfigManager.keyCode(for: config.key) else {
            fputs("Warning: Unknown key '\(config.key)' in config — hotkey \(id) not registered\n", stderr)
            return
        }
        let modifiers = ConfigManager.modifierMask(for: config.modifiers)
        let hotkeyID = EventHotKeyID(signature: OSType(0x4B565354), id: id)
        var hotkeyRef: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
        hotkeyRefs.append(hotkeyRef)
    }

    /// Unregisters all hotkeys.
    public func unregister() {
        for ref in hotkeyRefs {
            if let r = ref {
                UnregisterEventHotKey(r)
            }
        }
        hotkeyRefs.removeAll()
    }

    /// Installs SIGTERM and SIGINT handlers to clean up hotkeys on forced termination.
    private func installSignalHandlers() {
        signal(SIGTERM) { _ in
            HotkeyManager.shared.unregister()
            exit(0)
        }
        signal(SIGINT) { _ in
            HotkeyManager.shared.unregister()
            exit(0)
        }
    }
}
