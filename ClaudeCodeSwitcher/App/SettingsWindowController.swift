import Cocoa
import SwiftUI

class SettingsWindowController: NSWindowController {
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Claude Code Switcher 设置"
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        
        self.init(window: window)
        
        // 使用 SwiftUI 视图
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        window.contentViewController = hostingController
    }
}