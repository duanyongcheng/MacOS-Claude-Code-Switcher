import Cocoa
import SwiftUI

class SettingsWindowController: NSWindowController, NSWindowDelegate {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
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

    override func showWindow(_ sender: Any?) {
        // 切换为普通应用，使其出现在 Dock 和 Cmd+Tab
        NSApp.setActivationPolicy(.regular)
        super.showWindow(sender)
        // 激活应用并将窗口置于最前
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // 当窗口将要关闭时调用
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 隐藏窗口而不是完全关闭
        sender.orderOut(nil)
        // 切换回 Agent 模式，从 Dock 和 Cmd+Tab 隐藏
        NSApp.setActivationPolicy(.accessory)
        return false // 返回 false 来阻止窗口被释放
    }
}