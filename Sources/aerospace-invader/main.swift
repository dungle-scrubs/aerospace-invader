import AerospaceInvaderCore
import Cocoa

let version = "0.2.1"  // x-release-please-version

func printHelp() {
    // Derive the displayed hotkeys and paths from the same sources the daemon uses, so help
    // text can't drift from the actual default bindings or config locations.
    let defaults = Config.default
    let back = ConfigManager.hotkeyDescription(defaults.back)
    let forward = ConfigManager.hotkeyDescription(defaults.forward)
    let toggle = ConfigManager.hotkeyDescription(defaults.toggle)
    let expand = ConfigManager.hotkeyDescription(defaults.expand)

    print(
        """
        aerospace-invader \(version)
        A workspace navigator and OSD for AeroSpace window manager

        USAGE:
            aerospace-invader [COMMAND]

        COMMANDS:
            daemon              Run as background daemon with hotkeys (default)
            tabs                Show compact workspace bar (auto-hides)
            expand              Show expanded grid view
            whichkey <mode>     Show keybindings for an AeroSpace mode
            hide                Hide any visible windows and exit

        OPTIONS:
            -h, --help          Show this help message
            -v, --version       Show version

        HOTKEYS (daemon mode, defaults):
            \(back)                  Previous workspace
            \(forward)                  Next workspace
            \(toggle)                  Toggle between current and previous workspace
            \(expand)                  Expand compact bar to grid view

        CONFIG:
            \(ConfigStore.configFile)    Hotkey configuration
            \(ConfigStore.orderFile)     Saved workspace order
        """)
}

// Handle --help and --version before starting the app
if CommandLine.arguments.count > 1 {
    let arg = CommandLine.arguments[1]
    if arg == "-h" || arg == "--help" {
        printHelp()
        exit(0)
    }
    if arg == "-v" || arg == "--version" {
        print("aerospace-invader \(version)")
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

// Parse mode args
if CommandLine.arguments.count > 1 {
    guard let mode = AppMode(rawValue: CommandLine.arguments[1]) else {
        fputs("Unknown mode: \(CommandLine.arguments[1])\n", stderr)
        fputs("Usage: aerospace-invader [daemon|tabs|expand|whichkey <mode>|hide]\n", stderr)
        exit(1)
    }
    delegate.mode = mode
}
if CommandLine.arguments.count > 2 {
    delegate.modeArg = CommandLine.arguments[2]
}

app.delegate = delegate
app.setActivationPolicy(.prohibited)
app.run()
