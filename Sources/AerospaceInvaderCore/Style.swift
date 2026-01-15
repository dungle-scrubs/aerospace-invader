import Cocoa

public struct Style {
    public static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    public static let smallFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    public static let bgColor = NSColor(white: 0.1, alpha: 0.95)
    public static let borderColor = NSColor(red: 0, green: 1, blue: 0, alpha: 0.6)
    public static let activeColor = NSColor(red: 0, green: 1, blue: 0, alpha: 1)
    public static let inactiveColor = NSColor(white: 0.5, alpha: 1)
    public static let textColor = NSColor.white
}
