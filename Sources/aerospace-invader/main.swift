import AerospaceInvaderCore
import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()

// Parse args
if CommandLine.arguments.count > 1 {
    delegate.mode = CommandLine.arguments[1]
}
if CommandLine.arguments.count > 2 {
    delegate.modeArg = CommandLine.arguments[2]
}

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
