# aerospace-invader

[![CI](https://github.com/dungle-scrubs/aerospace-invader/actions/workflows/ci.yml/badge.svg)](https://github.com/dungle-scrubs/aerospace-invader/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A workspace navigator and on-screen display for [AeroSpace](https://github.com/nikitabobko/AeroSpace), the i3-like tiling window manager for macOS.

## Features

- **Workspace cycling** - Navigate between non-empty workspaces with `⌥O` (back) and `⌥I` (forward)
- **Expandable OSD** - Compact pill bar that expands to a full grid view with `⌥.`
- **Drag-to-reorder** - Rearrange workspace order in expanded view
- **Persistent ordering** - Your custom workspace order is saved across sessions
- **Which-key display** - Shows keybindings for AeroSpace modes (service, resize, etc.)
- **Auto-enable** - Automatically enables AeroSpace if it's not running

## Requirements

- macOS 13.0+ (Apple Silicon or Intel)
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) window manager
- Swift 5.9+ (Xcode Command Line Tools or full Xcode)

## Installation

### Homebrew (recommended)

```bash
brew install dungle-scrubs/aerospace-invader/aerospace-invader
brew services start aerospace-invader
```

### From Source

```bash
git clone https://github.com/dungle-scrubs/aerospace-invader.git
cd aerospace-invader
make release
make install  # Installs to /usr/local/bin
```

### Manual Build

```bash
swift build -c release
cp .build/release/aerospace-invader /usr/local/bin/
```

## Usage

### Daemon Mode (recommended)

Run as a background daemon that listens for hotkeys:

```bash
aerospace-invader daemon
```

**Hotkeys:**
- `⌥O` - Previous workspace
- `⌥I` - Next workspace
- `⌥P` - Toggle between current and previous workspace
- `⌥.` - Expand compact bar to grid view

### One-shot Commands

```bash
aerospace-invader tabs      # Show compact workspace bar (auto-hides)
aerospace-invader expand    # Show expanded grid view
aerospace-invader whichkey service  # Show keybindings for 'service' mode
```

### Which-key Configuration

To show the which-key display when entering an AeroSpace mode, add this to your `~/.config/aerospace/aerospace.toml`:

```toml
[mode.main.binding]
alt-shift-semicolon = ['mode service', 'exec-and-forget /opt/homebrew/bin/aerospace-invader whichkey service']

[mode.service.binding]
# Close the which-key window when exiting service mode
esc = ['reload-config', 'mode main', 'exec-and-forget pkill -f "aerospace-invader whichkey"']
```

The `pkill` command is required because AeroSpace intercepts key events before they reach the which-key window.

### LaunchAgent (start at login)

Create `~/Library/LaunchAgents/com.aerospace-invader.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.aerospace-invader</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/aerospace-invader</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

Then:

```bash
launchctl load ~/Library/LaunchAgents/com.aerospace-invader.plist
```

## Configuration

Config files are stored in `~/.config/aerospace-invader/`:

- `config.json` - Hotkey configuration
- `order.json` - Saved workspace order

### Hotkeys

Create `~/.config/aerospace-invader/config.json` to customize hotkeys:

```json
{
  "back": { "key": "o", "modifiers": ["option"] },
  "forward": { "key": "i", "modifiers": ["option"] },
  "expand": { "key": ".", "modifiers": ["option"] },
  "toggle": { "key": "p", "modifiers": ["option"] }
}
```

**Supported modifiers:** `option`/`alt`, `command`/`cmd`, `control`/`ctrl`, `shift`

**Supported keys:** `a-z`, `0-9`, `.`, `,`, `/`, `;`, `'`, `[`, `]`, `\`, `-`, `=`, `` ` ``, `space`, `return`, `tab`, `escape`, `delete`, `left`, `right`, `up`, `down`

## Development

```bash
make build    # Debug build
make release  # Release build
make test     # Run tests (requires full Xcode)
make lint     # Run SwiftLint
make format   # Run swift-format
make run      # Build and run daemon
```

### Testing

Tests require full Xcode (not just Command Line Tools):

```bash
# Check current selection
xcode-select -p

# If it shows /Library/Developer/CommandLineTools, switch to Xcode:
sudo xcode-select -s /Applications/Xcode.app

# Then run tests
make test
```

### Dependencies

- [SwiftLint](https://github.com/realm/SwiftLint): `brew install swiftlint`
- [swift-format](https://github.com/apple/swift-format): `brew install swift-format`

## License

MIT
