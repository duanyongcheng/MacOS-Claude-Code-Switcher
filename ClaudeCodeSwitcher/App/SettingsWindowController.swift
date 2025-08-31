import Cocoa
import SwiftUI

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Claude Code Switcher 设置"
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        
        self.init(window: window)
        
        // 设置窗口代理以处理关闭事件
        window.delegate = self
        
        // 使用 SwiftUI 视图
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        window.contentViewController = hostingController
    }
    
    // 当窗口将要关闭时调用
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 隐藏窗口而不是完全关闭
        sender.orderOut(nil)
        return false // 返回 false 来阻止窗口被释放
    }
}