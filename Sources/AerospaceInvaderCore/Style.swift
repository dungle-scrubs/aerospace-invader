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
    /// Dimmed text for secondary content (e.g. which-key command descriptions).
    public static let secondaryTextColor = NSColor(white: 0.7, alpha: 1)
    /// Thin separator line color.
    public static let separatorColor = NSColor(white: 0.3, alpha: 1)
    /// Amber accent for which-key key labels.
    public static let keyColor = NSColor(red: 1, green: 0.8, blue: 0, alpha: 1)
    /// Background for the active workspace tile in expanded grid view.
    public static let tileActiveColor = NSColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1)
    /// Background for inactive workspace tiles in expanded grid view.
    public static let tileInactiveColor = NSColor(white: 0.25, alpha: 1)
    /// Faint green fill behind the active workspace pill in compact view.
    public static let activeHighlightColor = NSColor(red: 0, green: 1, blue: 0, alpha: 0.15)
    /// Neutral border around the OSD window chrome.
    public static let windowBorderColor = NSColor(white: 0.25, alpha: 1)
    /// Red fill for the expanded-view close button.
    public static let closeButtonColor = NSColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
}
