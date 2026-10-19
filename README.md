# aerospace-invader

[![CI](https://github.com/dungle-scrubs/aerospace-invader/actions/workflows/ci.yml/badge.svg)](https://github.com/dungle-scrubs/aerospace-invader/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

See where you are as you page through AeroSpace workspaces.

See your current [AeroSpace](https://github.com/nikitabobko/AeroSpace) workspace, which others have windows, and where ⌥O or ⌥I will take you next. When you forget a mode shortcut, look it up in a which-key popup instead of a menu bar app. AeroSpace still handles window tiling.

```console
$ aerospace-invader --help
...
HOTKEYS (daemon mode, defaults):
    ⌥O                  Previous workspace
    ⌥I                  Next workspace
    ⌥P                  Toggle between current and previous workspace
    ⌥.                  Expand compact bar to grid view
...
```

## Install

Requires macOS 13.0 or later on Apple Silicon or Intel, with [AeroSpace installed and running](https://nikitabobko.github.io/AeroSpace/guide#installation) and its `aerospace` CLI available.

Download v0.2.1, the current published release, for your Mac:

```bash
version=0.2.1
archive="aerospace-invader-v${version}-darwin-$(uname -m).tar.gz"
curl -fL -o "$archive" "https://github.com/dungle-scrubs/aerospace-invader/releases/download/v${version}/$archive"
shasum -a 256 "$archive"
```

Compare the hash with the matching architecture's SHA256 in the [release notes](https://github.com/dungle-scrubs/aerospace-invader/releases/latest) before extracting:

```bash
tar -xzf "$archive"
mkdir -p "$HOME/.local/bin"
install -m 755 aerospace-invader "$HOME/.local/bin/aerospace-invader"
export PATH="$HOME/.local/bin:$PATH"
aerospace-invader --version
```

Keep the `PATH` line in your shell profile for future terminals. To build from source, see [Contributing](#contributing).

## Usage

### Page through occupied workspaces

```bash
aerospace-invader daemon
```

Press ⌥O to go back and ⌥I to go forward through non-empty workspaces in the bar's order. The bar highlights your destination before it hides, and Ctrl+C stops the foreground daemon.

### Check where you are without starting the daemon

```bash
aerospace-invader tabs
```

The compact bar lists occupied workspaces and highlights the current one when it is in the list. It then hides and exits.

### Put workspaces in your preferred order

```bash
aerospace-invader expand
```

Drag workspace tiles to change the saved order, or click a tile to switch to that workspace. With the daemon running, ⌥. opens the grid without a separate command.

### Look up shortcuts when you enter a mode

Merge this binding into your AeroSpace configuration's existing `[mode.main.binding]` table:

```toml
[mode.main.binding]
alt-shift-semicolon = ['mode service', 'exec-and-forget "$HOME/.local/bin/aerospace-invader" whichkey service']
```

Use your installed binary's path if it differs, then reload your AeroSpace configuration. Press ⌥⇧; to enter your existing `service` mode and see its shortcuts until you leave the mode.

## Reference

```text
aerospace-invader [COMMAND]
```

| Command | Behavior |
| --- | --- |
| `daemon` | Register global hotkeys. This is the default when no command is given. |
| `tabs` | Show the compact bar, then hide and exit. |
| `expand` | Show the workspace grid for selection and reordering. |
| `whichkey [mode]` | Show bindings for an AeroSpace mode. The default mode is `service`. |
| `hide` | Exit this invocation. It does not stop a running daemon or close another process's overlay. |
| `--help`, `-h` | Print usage, default hotkeys, and configuration paths. |
| `--version`, `-v` | Print the version. |

### Default hotkeys

These bindings apply while the daemon runs:

| Hotkey | Action |
| --- | --- |
| ⌥O | Previous non-empty workspace, wrapping at the start. |
| ⌥I | Next non-empty workspace, wrapping at the end. |
| ⌥P | Switch between the current and previous workspace. |
| ⌥. | Expand a visible compact bar, open the grid, or dismiss a visible grid. |

If a hotkey conflicts with another app or an AeroSpace binding, choose a different binding in `config.json`.

### Configuration

Files live in `~/.config/aerospace-invader/`:

- `config.json` stores daemon hotkeys. Omitted bindings keep their defaults.
- `order.json` stores the workspace order saved by drag-to-reorder.

For example, this `config.json` changes only forward and backward paging:

```json
{
  "back": { "key": "left", "modifiers": ["option", "shift"] },
  "forward": { "key": "right", "modifiers": ["option", "shift"] }
}
```

Restart the daemon after changing hotkeys. The configuration directory is fixed. `XDG_CONFIG_HOME` does not change it.

### Security and errors

The app runs the local `aerospace` CLI and reads its workspace and binding data. It tries `aerospace enable on` if AeroSpace does not respond. The which-key popup uses a mouse event tap for dismissal, not a global keyboard event tap. macOS permissions can affect click-to-dismiss.

`--help` and `--version` exit with code 0. Unknown commands exit with code 1. AeroSpace startup errors appear in a dialog and on stderr, so exit status alone is not a health check.

[Full reference](docs/reference.md) covers supported keys, binary discovery, permissions, and starting at login. Report vulnerabilities through the [security policy](SECURITY.md).

## Contributing

Building requires Swift 5.9 or later. Tests use Swift Testing and require Xcode 16 or later with a Swift 6 toolchain selected. Check the selection with `xcode-select -p`.

```bash
git clone https://github.com/dungle-scrubs/aerospace-invader.git
cd aerospace-invader
make build
make test
make release
```

To install a source build in the same location as the prebuilt instructions:

```bash
mkdir -p "$HOME/.local/bin"
make install INSTALL_PATH="$HOME/.local/bin"
```

For lint, formatting, and commit hooks:

```bash
brew install swiftlint swift-format lefthook trufflehog
lefthook install
make lint
make format
```

`make run` builds and starts the daemon. See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution process and commit conventions.

## License

[MIT](LICENSE).
