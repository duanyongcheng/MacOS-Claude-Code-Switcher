import Cocoa
import SwiftUI

// MARK: - Settings Window Controller 设置窗口控制器

/// 设置窗口控制器
/// Manages settings window display and lifecycle
class SettingsWindowController: NSWindowController, NSWindowDelegate {

    // MARK: - Initialization

    /// 初始化设置窗口
    /// Initialize settings window
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

    // MARK: - Window Management

    /// 显示窗口
    /// Show window
    override func showWindow(_ sender: Any?) {
        // 切换为普通应用，使其出现在 Dock 和 Cmd+Tab
        // Switch to regular app to appear in Dock and Cmd+Tab
        NSApp.setActivationPolicy(.regular)
        super.showWindow(sender)
        // 激活应用并将窗口置于最前
        // Activate app and bring window to front
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    /// 窗口即将关闭
    /// Window should close
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 隐藏窗口而不是完全关闭
        // Hide window instead of closing
        sender.orderOut(nil)
        // 切换回 Agent 模式，从 Dock 和 Cmd+Tab 隐藏
        // Switch back to accessory mode, hide from Dock and Cmd+Tab
        NSApp.setActivationPolicy(.accessory)
        return false // 返回 false 来阻止窗口被释放 / Return false to prevent window deallocation
    }
}