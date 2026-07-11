@testable import AerospaceInvaderCore
import Foundation
import Testing

@Suite("BindingFormatter")
struct BindingFormatterTests {

    // MARK: - Categorize

    @Test("movement commands categorize as Movement")
    func categorizeMovement() {
        #expect(BindingFormatter.categorize(key: "h", cmd: "focus left") == .movement)
        #expect(BindingFormatter.categorize(key: "alt-h", cmd: "move left") == .movement)
        #expect(BindingFormatter.categorize(key: "j", cmd: "join-with down") == .movement)
    }

    @Test("layout commands categorize as Layout")
    func categorizeLayout() {
        #expect(BindingFormatter.categorize(key: "s", cmd: "layout v_accordion") == .layout)
        #expect(BindingFormatter.categorize(key: "f", cmd: "fullscreen") == .layout)
    }

    @Test("mode-exit commands categorize as Exit")
    func categorizeExit() {
        #expect(BindingFormatter.categorize(key: "esc", cmd: "mode main") == .exit)
        #expect(BindingFormatter.categorize(key: "r", cmd: "reload-config; mode main") == .exit)
    }

    @Test("everything else categorizes as Actions")
    func categorizeActions() {
        #expect(BindingFormatter.categorize(key: "c", cmd: "close-all-windows-but-current") == .actions)
        #expect(BindingFormatter.categorize(key: "x", cmd: "enable toggle") == .actions)
    }

    // MARK: - Format key

    @Test("formatKey renders modifiers as glyphs")
    func formatKeyModifiers() {
        #expect(BindingFormatter.formatKey("alt-h") == "⌥h")
        #expect(BindingFormatter.formatKey("cmd-shift-l") == "⌘⇧l")
        #expect(BindingFormatter.formatKey("ctrl-alt-p") == "⌃⌥p")
    }

    @Test("formatKey renders special key names as symbols")
    func formatKeySpecial() {
        #expect(BindingFormatter.formatKey("alt-semicolon") == "⌥;")
        #expect(BindingFormatter.formatKey("backspace") == "⌫")
        #expect(BindingFormatter.formatKey("esc") == "Esc")
    }

    @Test("formatKey passes through a plain key")
    func formatKeyPlain() {
        #expect(BindingFormatter.formatKey("h") == "h")
    }

    // MARK: - Format command

    @Test("formatCmd simplifies known commands")
    func formatCmd() {
        #expect(BindingFormatter.formatCmd("flatten-workspace-tree") == "flatten")
        #expect(BindingFormatter.formatCmd("layout floating tiling") == "toggle float")
        #expect(BindingFormatter.formatCmd("focus left; mode main") == "focus left")
    }

    // MARK: - Grouping

    @Test("group buckets bindings into categories in display order")
    func groupOrdersCategories() {
        let bindings = [
            "h": "focus left",       // Movement
            "s": "layout v_accordion", // Layout
            "x": "enable toggle",    // Actions
            "esc": "mode main"       // Exit
        ]
        let groups = BindingFormatter.group(bindings)
        #expect(groups.map(\.category) == [.movement, .layout, .actions, .exit])
    }

    @Test("group omits empty categories and sorts items by key")
    func groupSortsAndOmits() {
        let bindings = ["l": "focus right", "h": "focus left"]
        let groups = BindingFormatter.group(bindings)
        #expect(groups.count == 1)
        #expect(groups[0].category == .movement)
        #expect(groups[0].items.map(\.key) == ["h", "l"])
    }
}
