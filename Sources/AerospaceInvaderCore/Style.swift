import Cocoa

/// Shared visual constants for the workspace OSD.
/// All colors use a dark theme with green accents matching the AeroSpace aesthetic.
public struct Style {
    /// Primary monospaced font for workspace labels.
    public static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    /// Smaller monospaced font for secondary text.
    public static let smallFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    /// Semi-transparent dark background color.
    public static let bgColor = NSColor(white: 0.1, alpha: 0.95)
    /// Green border color for active elements and window borders.
    public static let borderColor = NSColor(red: 0, green: 1, blue: 0, alpha: 0.6)
    /// Bright green color for the active workspace indicator.
    public static let activeColor = NSColor(red: 0, green: 1, blue: 0, alpha: 1)
    /// Muted gray for inactive workspace labels.
    public static let inactiveColor = NSColor(white: 0.5, alpha: 1)
    /// Default text color (white).
    public static let textColor = NSColor.white
}
