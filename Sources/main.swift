import AppKit

let args = CommandLine.arguments
if args.count >= 3 && args[1] == "--render-icon" {
    IconRenderer.render(to: args[2])
    exit(0)
}
if args.count >= 3 && args[1] == "--render-dmg-background" {
    IconRenderer.renderInstallerBackground(to: args[2])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
