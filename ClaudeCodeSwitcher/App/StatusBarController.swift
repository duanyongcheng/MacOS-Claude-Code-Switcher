import Cocoa
import UserNotifications

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var configManager: ConfigManager!
    private var settingsWindowController: SettingsWindowController?
    private var balanceStatus: BalanceMenuStatus = .idle
    
    override init() {
        super.init()
        print("StatusBarController init 开始")
        configManager = ConfigManager.shared
        print("ConfigManager 获取成功")
        setupStatusBar()
        print("setupStatusBar 完成")
        setupMenu()
        print("setupMenu 完成")
        observeConfigChanges()
        print("observeConfigChanges 完成")
        requestNotificationPermission()
        
        // 延迟重建菜单，确保配置已加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.rebuildMenu()
        }
        
        print("StatusBarController init 完成")
    }
    
    private func setupStatusBar() {
        print("setupStatusBar 被调用")
        statusItem = NSStatusBar.system.statusItem(withLength: 20)  // 设置稍宽一点的固定宽度
        print("statusItem 创建成功")
        
        if let button = statusItem.button {
            print("获取到 statusItem.button")
            // 使用自定义图标 ccw.png
            if let image = NSImage(named: "ccw") {
                // 调整图标大小以适应状态栏 - 使用 30x30
                let resizedImage = NSImage(size: NSSize(width: 30, height: 30))
                resizedImage.lockFocus()
                image.draw(in: NSRect(x: 0, y: 0, width: 30, height: 30),
                          from: NSRect(origin: .zero, size: image.size),
                          operation: .sourceOver,
                          fraction: 1.0)
                resizedImage.unlockFocus()
                
                button.image = resizedImage
                button.image?.isTemplate = true
                print("设置自定义图标: ccw.png 成功 (30x30)")
            } else if let bundlePath = Bundle.main.path(forResource: "ccw", ofType: "png"),
                      let image = NSImage(contentsOfFile: bundlePath) {
                // 调整图标大小以适应状态栏 - 使用 30x30
                let resizedImage = NSImage(size: NSSize(width: 30, height: 30))
                resizedImage.lockFocus()
                image.draw(in: NSRect(x: 0, y: 0, width: 30, height: 30),
                          from: NSRect(origin: .zero, size: image.size),
                          operation: .sourceOver,
                          fraction: 1.0)
                resizedImage.unlockFocus()
                
                button.image = resizedImage
                button.image?.isTemplate = true
                print("从 bundle 路径加载图标: ccw.png 成功 (30x30)")
            } else if let image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Claude Code Switcher") {
                button.image = image
                button.image?.isTemplate = true
                print("使用系统图标: brain.head.profile 作为后备")
            } else {
                // 使用文本作为后备
                button.title = "🧠"
                print("使用文本图标: 🧠")
            }
        } else {
            print("错误: 无法获取 statusItem.button")
        }
    }
    
    private func setupMenu() {
        menu = NSMenu()
        statusItem.menu = menu
        rebuildMenu()
    }
    
    private func rebuildMenu() {
        menu.removeAllItems()
        
        // 添加标题
        let titleItem = NSMenuItem(title: "Claude Code Switcher", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        let titleFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.labelColor
        ]
        titleItem.attributedTitle = NSAttributedString(string: "Claude Code Switcher", attributes: titleAttributes)
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // 添加当前提供商信息
        let currentProvider = configManager.currentProvider
        if let current = currentProvider {
            let currentHeaderItem = NSMenuItem(title: "当前配置", action: nil, keyEquivalent: "")
            currentHeaderItem.isEnabled = false
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            currentHeaderItem.attributedTitle = NSAttributedString(string: "当前配置", attributes: headerAttributes)
            menu.addItem(currentHeaderItem)
            
            let currentItem = NSMenuItem(title: "  ✓ \(current.name)", action: nil, keyEquivalent: "")
            currentItem.isEnabled = false
            let currentAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.systemBlue
            ]
            currentItem.attributedTitle = NSAttributedString(string: "  ✓ \(current.name)", attributes: currentAttributes)
            menu.addItem(currentItem)
        }
        
        // 添加余额信息
        let balanceItem = NSMenuItem(title: balanceStatus.menuTitle(for: currentProvider), action: nil, keyEquivalent: "")
        balanceItem.isEnabled = false
        balanceItem.attributedTitle = NSAttributedString(string: balanceStatus.menuTitle(for: currentProvider), attributes: balanceStatus.menuAttributes)
        balanceItem.toolTip = balanceStatus.tooltip(for: currentProvider)
        menu.addItem(balanceItem)
        
        if let provider = currentProvider {
            let urlTitle = "地址: \(provider.url)"
            let urlItem = NSMenuItem(title: urlTitle, action: nil, keyEquivalent: "")
            urlItem.isEnabled = false
            let urlAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            urlItem.attributedTitle = NSAttributedString(string: urlTitle, attributes: urlAttributes)
            menu.addItem(urlItem)
        }
        menu.addItem(NSMenuItem.separator())
        
        // 添加 API 提供商列表
        let providers = configManager.getProviders()
        
        if providers.isEmpty {
            let noProvidersItem = NSMenuItem(title: "⚠️ 暂无配置的提供商", action: nil, keyEquivalent: "")
            noProvidersItem.isEnabled = false
            let warningAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.systemOrange
            ]
            noProvidersItem.attributedTitle = NSAttributedString(string: "⚠️ 暂无配置的提供商", attributes: warningAttributes)
            menu.addItem(noProvidersItem)
        } else {
            let switchHeaderItem = NSMenuItem(title: "切换到", action: nil, keyEquivalent: "")
            switchHeaderItem.isEnabled = false
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            switchHeaderItem.attributedTitle = NSAttributedString(string: "切换到", attributes: headerAttributes)
            menu.addItem(switchHeaderItem)
            
            for provider in providers {
                var title = provider.name
                var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
                
                // 标记当前选中的提供商
                if provider.id == currentProvider?.id {
                    title = "  ● " + title
                    attributes[.foregroundColor] = NSColor.systemBlue
                    
                    if let balanceInline = balanceStatus.inlineText(for: provider) {
                        title += " · \(balanceInline)"
                    }
                } else if provider.isValid {
                    title = "  ○ " + title
                    attributes[.foregroundColor] = NSColor.labelColor
                } else {
                    title = "  ⚠ " + title + " (未配置)"
                    attributes[.foregroundColor] = NSColor.tertiaryLabelColor
                }
                
                let item = NSMenuItem(title: title, action: #selector(selectProvider(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = provider
                item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
                
                // 添加工具提示
                if !provider.isValid {
                    item.toolTip = "需要配置 API 密钥"
                } else if provider.id == currentProvider?.id {
                    item.toolTip = "当前使用的配置"
                } else {
                    item.toolTip = "点击切换到此配置"
                }
                
                // 检查 API 密钥是否配置
                if !provider.isValid {
                    item.isEnabled = false
                }
                
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 添加操作区域
        let actionsHeaderItem = NSMenuItem(title: "操作", action: nil, keyEquivalent: "")
        actionsHeaderItem.isEnabled = false
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        actionsHeaderItem.attributedTitle = NSAttributedString(string: "操作", attributes: headerAttributes)
        menu.addItem(actionsHeaderItem)
        
        // 添加设置菜单项
        let settingsItem = NSMenuItem(title: "  ⚙️  设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.toolTip = "打开设置窗口管理 API 配置"
        menu.addItem(settingsItem)
        
        // 添加关于菜单项
        let aboutItem = NSMenuItem(title: "  ℹ️  关于", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.toolTip = "关于 Claude Code Switcher"
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 添加退出菜单项
        let quitItem = NSMenuItem(title: "  退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.toolTip = "退出 Claude Code Switcher"
        menu.addItem(quitItem)
    }
    
    func updateBalanceStatus(_ status: BalanceMenuStatus) {
        balanceStatus = status
        rebuildMenu()
    }
    
    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let provider = sender.representedObject as? APIProvider else { return }
        
        if provider.isValid {
            configManager.setCurrentProvider(provider)
            balanceStatus = .idle
            rebuildMenu()
            showNotification(title: "已切换到: \(provider.name)")
        } else {
            showNotification(title: "请先配置 \(provider.name) 的 API 密钥", subtitle: "点击设置菜单进行配置")
        }
    }
    
    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    private func observeConfigChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configDidChange),
            name: .configDidChange,
            object: nil
        )
    }
    
    @objc private func configDidChange() {
        balanceStatus = .idle
        rebuildMenu()
    }
    
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("通知权限请求失败: \(error)")
            }
        }
    }
    
    private func showNotification(title: String, subtitle: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("发送通知失败: \(error)")
            }
        }
    }
}

enum BalanceMenuStatus {
    case idle
    case loading
    case success(amount: Double, currency: String)
    case failure(message: String)
    
    func menuTitle(for provider: APIProvider?) -> String {
        switch self {
        case .idle:
            return provider == nil ? "余额：未选择配置" : "余额：未查询"
        case .loading:
            return "余额：查询中..."
        case .success(let amount, let currency):
            let prefix = amount < 5.0 ? "⚠️ " : ""
            let amountText = "\(currency)\(String(format: "%.2f", amount))"
            return "\(prefix)余额：\(amountText)"
        case .failure:
            return "⚠️ 余额：获取失败"
        }
    }
    
    func inlineText(for provider: APIProvider?) -> String? {
        guard provider != nil else { return nil }
        
        switch self {
        case .idle:
            return "余额未查"
        case .loading:
            return "余额查询中"
        case .success(let amount, let currency):
            let amountText = "\(currency)\(String(format: "%.2f", amount))"
            return "余额 \(amountText)"
        case .failure:
            return "余额失败"
        }
    }
    
    var menuAttributes: [NSAttributedString.Key: Any] {
        var color: NSColor = .secondaryLabelColor
        switch self {
        case .success(let amount, _):
            color = amount < 5.0 ? .systemOrange : .systemGreen
        case .failure:
            color = .systemOrange
        case .loading:
            color = .secondaryLabelColor
        case .idle:
            color = .secondaryLabelColor
        }
        
        return [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color
        ]
    }
    
    func tooltip(for provider: APIProvider?) -> String? {
        switch self {
        case .idle:
            return provider == nil ? "选择配置后可查询余额" : "尚未查询余额"
        case .loading:
            return "正在查询余额..."
        case .success(let amount, _):
            return amount < 5.0 ? "余额低于 $5，建议尽快充值" : "余额状态正常"
        case .failure(let message):
            return message
        }
    }
}
