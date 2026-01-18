import AerospaceInvaderCore
import Cocoa

let version = "0.1.9"

func printHelp() {
    print("""
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

        HOTKEYS (daemon mode):
            ⌥O                  Previous workspace
            ⌥I                  Next workspace
            ⌥P                  Toggle between current and previous workspace
            ⌥.                  Expand compact bar to grid view

        CONFIG:
            ~/.config/aerospace-invader/config.json    Hotkey configuration
            ~/.config/aerospace-invader/order.json     Saved workspace order
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
    delegate.mode = CommandLine.arguments[1]
}
if CommandLine.arguments.count > 2 {
    delegate.modeArg = CommandLine.arguments[2]
}

app.delegate = delegate
app.setActivationPolicy(.prohibited)
app.run()
