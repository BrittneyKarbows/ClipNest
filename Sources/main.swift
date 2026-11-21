import AppKit

AppController.demo = CommandLine.arguments.contains("--demo")
let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.run()
