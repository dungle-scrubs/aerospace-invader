import Foundation

/// A which-key display category, in display order.
enum BindingCategory: String, CaseIterable {
    case movement = "Movement"
    case layout = "Layout"
    case actions = "Actions"
    case exit = "Exit"
}

/// Pure formatting and categorization for AeroSpace mode bindings. Now a thin façade over
/// `KeyLexicon` for key glyphs — the deep module that owns every `alt → ⌥` mapping — so
/// hotkey registration and which-key display share one table.
enum BindingFormatter {
    /// A named group of bindings for display.
    struct Group {
        let category: BindingCategory
        let items: [(key: String, cmd: String)]
    }

    /// Non-modifier key names that render as a symbol. Forwards to `KeyLexicon` — one table.
    private static let specialKeys: [String: String] = KeyLexicon.specialKeySymbols

    /// Command simplifications applied for display, in order.
    private static let cmdReplacements: [(from: String, to: String)] = [
        ("; mode main", ""),
        ("flatten-workspace-tree", "flatten"),
        ("close-all-windows-but-current", "close others"),
        ("layout floating tiling", "toggle float"),
        ("reload-config", "reload"),
        ("join-with ", "join "),
        ("enable toggle", "toggle enable")
    ]

    /// Groups raw key→command bindings into display categories with sorted items, in display order.
    static func group(_ bindings: [String: String]) -> [Group] {
        var byCategory: [BindingCategory: [(key: String, cmd: String)]] = [:]
        for (key, cmd) in bindings {
            byCategory[categorize(key: key, cmd: cmd), default: []].append((key: key, cmd: cmd))
        }
        return BindingCategory.allCases.compactMap { category in
            guard let items = byCategory[category], !items.isEmpty else { return nil }
            return Group(category: category, items: items.sorted { $0.key < $1.key })
        }
    }

    /// Categorizes a binding into Movement, Layout, Exit, or Actions.
    static func categorize(key: String, cmd: String) -> BindingCategory {
        if cmd.hasPrefix("move ") || cmd.hasPrefix("join-with ") || cmd.hasPrefix("focus ") {
            return .movement
        }
        if cmd.hasPrefix("layout ") || cmd.contains("fullscreen") {
            return .layout
        }
        if cmd.contains("mode main") && (key == "esc" || cmd.contains("reload")) {
            return .exit
        }
        return .actions
    }

    /// Converts a raw AeroSpace key string (e.g. `alt-shift-h`) to readable symbols (`⌥⇧H`).
    /// Forwards to `KeyLexicon` so hotkey and which-key share one implementation.
    static func formatKey(_ key: String) -> String {
        KeyLexicon.formatKey(key)
    }

    /// Simplifies a raw AeroSpace command string for display.
    static func formatCmd(_ cmd: String) -> String {
        var result = cmd
        for replacement in cmdReplacements {
            result = result.replacingOccurrences(of: replacement.from, with: replacement.to)
        }
        return result
    }
}
