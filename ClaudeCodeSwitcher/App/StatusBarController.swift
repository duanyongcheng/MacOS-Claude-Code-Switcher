import Cocoa
import UserNotifications

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var configManager: ConfigManager!
    private var settingsWindowController: SettingsWindowController?
    
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
        print("StatusBarController init 完成")
    }
    
    private func setupStatusBar() {
        print("setupStatusBar 被调用")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        print("statusItem 创建成功")
        
        if let button = statusItem.button {
            print("获取到 statusItem.button")
            // 尝试使用不同的系统图标
            if let image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Claude Code Switcher") {
                button.image = image
                print("设置图标: brain.head.profile 成功")
            } else if let image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Claude Code Switcher") {
                button.image = image
                print("设置图标: brain 成功")
            } else if let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Claude Code Switcher") {
                button.image = image
                print("设置图标: cpu 成功")
            } else {
                // 使用文本作为后备
                button.title = "🧠"
                print("使用文本图标: 🧠")
            }
            button.image?.isTemplate = true
            print("设置 isTemplate = true")
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
        let titleFont = NSFont.boldSystemFont(ofSize: 13)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.secondaryLabelColor
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
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            currentHeaderItem.attributedTitle = NSAttributedString(string: "当前配置", attributes: headerAttributes)
            menu.addItem(currentHeaderItem)
            
            let currentItem = NSMenuItem(title: "  ✓ \(current.name)", action: nil, keyEquivalent: "")
            currentItem.isEnabled = false
            let currentAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.systemGreen
            ]
            currentItem.attributedTitle = NSAttributedString(string: "  ✓ \(current.name)", attributes: currentAttributes)
            menu.addItem(currentItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        // 添加 API 提供商列表
        let providers = configManager.getProviders()
        
        if providers.isEmpty {
            let noProvidersItem = NSMenuItem(title: "⚠️ 暂无配置的提供商", action: nil, keyEquivalent: "")
            noProvidersItem.isEnabled = false
            menu.addItem(noProvidersItem)
        } else {
            let switchHeaderItem = NSMenuItem(title: "切换到", action: nil, keyEquivalent: "")
            switchHeaderItem.isEnabled = false
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            switchHeaderItem.attributedTitle = NSAttributedString(string: "切换到", attributes: headerAttributes)
            menu.addItem(switchHeaderItem)
            
            for provider in providers {
                var title = provider.name
                var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
                
                // 标记当前选中的提供商
                if provider.id == currentProvider?.id {
                    title = "  ✓ " + title
                    attributes[.foregroundColor] = NSColor.systemGreen
                } else if provider.isValid {
                    title = "      " + title
                    attributes[.foregroundColor] = NSColor.labelColor
                } else {
                    title = "  ⚠️ " + title + " (未配置)"
                    attributes[.foregroundColor] = NSColor.secondaryLabelColor
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
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        actionsHeaderItem.attributedTitle = NSAttributedString(string: "操作", attributes: headerAttributes)
        menu.addItem(actionsHeaderItem)
        
        // 添加设置菜单项
        let settingsItem = NSMenuItem(title: "  ⚙️  设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.toolTip = "打开设置窗口管理 API 配置"
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 添加退出菜单项
        let quitItem = NSMenuItem(title: "  ⏻  退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.toolTip = "退出 Claude Code Switcher"
        menu.addItem(quitItem)
    }
    
    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let provider = sender.representedObject as? APIProvider else { return }
        
        if provider.isValid {
            configManager.setCurrentProvider(provider)
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