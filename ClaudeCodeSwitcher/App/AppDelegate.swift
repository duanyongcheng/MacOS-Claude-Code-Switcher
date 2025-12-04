import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("applicationDidFinishLaunching 被调用")
        setupApplication()
        print("setupApplication 完成")
        setupMenuBar()
        print("setupMenuBar 完成")
        statusBarController = StatusBarController()
        print("statusBarController 创建完成")

        if ConfigManager.shared.proxyModeEnabled {
            LocalProxyService.shared.start()
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        LocalProxyService.shared.stop()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 即使关闭最后一个窗口也不退出应用（状态栏应用）
        return false
    }
    
    private func setupApplication() {
        // 隐藏 Dock 图标（仅状态栏运行）
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupMenuBar() {
        // 创建主菜单
        let mainMenu = NSMenu()
        
        // 应用菜单
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于 Claude Code Switcher", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出 Claude Code Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 编辑菜单 - 这是支持复制粘贴的关键
        let editMenuItem = NSMenuItem()
        editMenuItem.title = "编辑"
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // 窗口菜单
        let windowMenuItem = NSMenuItem()
        windowMenuItem.title = "窗口"
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "关于 Claude Code Switcher"
        alert.informativeText = """
Claude Code Switcher 是一个帮助您快速切换不同 Claude API 配置的工具。

🔗 开源仓库
https://github.com/duanyongcheng/MacOS-Claude-Code-Switcher

✨ 特性
• 快速切换多个 API 配置
• 实时监控 Claude 进程状态
• 使用量统计和分析
• 代理设置支持
• 开机自动启动

感谢您的使用！
"""
        alert.alertStyle = .informational
        alert.addButton(withTitle: "访问仓库")
        alert.addButton(withTitle: "确定")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 打开 GitHub 仓库
            if let url = URL(string: "https://github.com/duanyongcheng/MacOS-Claude-Code-Switcher") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}