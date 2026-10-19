# aerospace-invader reference

[Return to the README](../README.md).

## Hotkey configuration

`~/.config/aerospace-invader/config.json` accepts four bindings. These are the defaults:

```json
{
  "back": { "key": "o", "modifiers": ["option"] },
  "forward": { "key": "i", "modifiers": ["option"] },
  "expand": { "key": ".", "modifiers": ["option"] },
  "toggle": { "key": "p", "modifiers": ["option"] }
}
```

Missing bindings retain their defaults. A binding with no `modifiers` field uses `["option"]`. A malformed file falls back to the default configuration and logs an error to stderr. Configuration loads when the process starts, not when the file changes.

| Modifier | Accepted spellings |
| --- | --- |
| Option | `option`, `alt` |
| Command | `command`, `cmd` |
| Control | `control`, `ctrl` |
| Shift | `shift` |

Supported keys are:

- Letters `a` through `z` and digits `0` through `9`.
- Punctuation `.`, `,`, `/`, `;`, `'`, `[`, `]`, `\`, `-`, `=`, and `` ` ``.
- `space`, `return`, `tab`, `escape`, `delete`, `left`, `right`, `up`, and `down`.

Key and modifier names are case-insensitive. Unknown keys are not registered. Unknown modifiers contribute no modifier flag.

## Workspace order

`~/.config/aerospace-invader/order.json` is a JSON array of workspace names. The app preserves saved order for currently non-empty workspaces and appends newly encountered workspaces. Empty workspaces drop out of the saved list when it is reconciled.

Forward and backward navigation wrap through this order across all monitors. The toggle action uses AeroSpace's `workspace-back-and-forth` command rather than the next or previous entry in the list.

## Which-key dismissal

`whichkey` reads bindings from AeroSpace's configuration for the requested mode. Omitting the mode selects `service`. The mode must exist in your AeroSpace configuration.

The popup checks the current AeroSpace mode and closes when it changes. Escape closes the popup when it receives that key event. Mouse clicks dismiss it when the event tap is available.

If stderr reports `Failed to create event tap`, click-to-dismiss is unavailable. The diagnostic suggests checking macOS Accessibility permissions for the process that runs the command. Mode-exit dismissal does not depend on the mouse event tap.

## Binary discovery and process behavior

The app looks for the AeroSpace CLI in this order:

1. `/opt/homebrew/bin/aerospace`.
2. `/usr/local/bin/aerospace`.
3. The result of `which aerospace` using the process's `PATH`.

The `PATH` fallback must be an absolute path to an executable file. Both that file and its parent directory must not be writable by the group or by other users. The two fixed installation paths are checked for existence without that additional permission check.

AeroSpace subprocess queries have a five-second timeout. Workspace switches run without waiting for completion. If the initial workspace query fails, the app attempts `aerospace enable on`; it does not launch `AeroSpace.app` itself.

`hide` terminates only its own process. There is no cross-process command to stop an existing daemon or dismiss its overlay. Ctrl+C stops a foreground daemon. A LaunchAgent-managed daemon must be stopped through launchd.

## Start at login

Stop any foreground daemon before enabling a LaunchAgent, so two processes do not compete for the same hotkeys.

Create `~/Library/LaunchAgents/com.aerospace-invader.plist`. Replace `/Users/YOUR_NAME` with your actual home directory. launchd does not expand `~` or `$HOME` in `ProgramArguments`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.aerospace-invader</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOUR_NAME/.local/bin/aerospace-invader</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

Validate and start the agent:

```bash
plutil -lint "$HOME/Library/LaunchAgents/com.aerospace-invader.plist"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.aerospace-invader.plist"
```

To stop it and remove it from the current login session:

```bash
launchctl bootout "gui/$(id -u)/com.aerospace-invader"
```

The plist remains on disk and starts the daemon at the next login. Remove the plist if you no longer want that behavior. Start AeroSpace before using the daemon's hotkeys.
