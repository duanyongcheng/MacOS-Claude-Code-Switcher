import Cocoa
import UserNotifications
import Combine

// MARK: - Status Bar Controller 状态栏控制器

/// 状态栏控制器
/// Manages status bar menu and provider switching
class StatusBarController: NSObject {
    // MARK: - Properties

    /// 状态栏项
    /// Status bar item
    private var statusItem: NSStatusItem!

    /// 菜单
    /// Menu instance
    private var menu: NSMenu!

    /// 配置管理器
    /// Configuration manager
    private var configManager: ConfigManager!

    /// 代理服务
    /// Proxy service
    private var proxyService: LocalProxyService!

    /// 设置窗口控制器
    /// Settings window controller
    private var settingsWindowController: SettingsWindowController?

    /// 余额状态
    /// Balance status
    private var balanceStatus: BalanceMenuStatus = .idle

    /// 余额服务
    /// Balance service
    private let balanceService = BalanceService()

    /// 折叠的分组集合
    /// Collapsed groups set
    private var collapsedGroups: Set<String> = []

    /// 代理服务订阅集合
    /// Proxy service subscriptions
    private var proxyServiceCancellables: Set<AnyCancellable> = []

    // MARK: - Initialization

    override init() {
        super.init()
        print("StatusBarController init 开始")
        configManager = ConfigManager.shared
        proxyService = LocalProxyService.shared
        print("ConfigManager 获取成功")
        setupStatusBar()
        print("setupStatusBar 完成")
        setupMenu()
        print("setupMenu 完成")
        observeConfigChanges()
        observeProxyService()
        print("observeConfigChanges 完成")
        requestNotificationPermission()
        fetchCurrentBalance()
        loadCollapsedGroups()

        // 延迟重建菜单，确保配置已加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.rebuildMenu()
        }

        print("StatusBarController init 完成")
    }

    // MARK: - Setup Methods

    /// 设置状态栏
    /// Setup status bar
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

    /// 设置菜单
    /// Setup menu
    private func setupMenu() {
        menu = NSMenu()
        statusItem.menu = menu
        rebuildMenu()
    }

    /// 重建菜单
    /// Rebuild menu with current configuration
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

        // 代理模式状态
        if configManager.proxyModeEnabled {
            let proxyStatusItem = NSMenuItem(title: "", action: #selector(toggleProxyMode), keyEquivalent: "")
            proxyStatusItem.target = self
            let poolCount = configManager.getProxyPoolProviders().count
            let statusText = "🔀 代理池模式 · \(poolCount) 个节点"
            let proxyAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.systemGreen
            ]
            proxyStatusItem.attributedTitle = NSAttributedString(string: statusText, attributes: proxyAttributes)
            proxyStatusItem.toolTip = "点击关闭代理池模式\n本地端口: \(configManager.proxyModePort)"
            menu.addItem(proxyStatusItem)

            let addressItem = NSMenuItem(title: "地址: http://127.0.0.1:\(configManager.proxyModePort)", action: nil, keyEquivalent: "")
            addressItem.isEnabled = false
            let addressAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            addressItem.attributedTitle = NSAttributedString(string: "地址: http://127.0.0.1:\(configManager.proxyModePort)", attributes: addressAttributes)
            menu.addItem(addressItem)

            // 显示当前请求状态
            if proxyService.isRequesting, let currentProvider = proxyService.currentRequestingProvider {
                let requestingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                requestingItem.isEnabled = false
                let requestingText = "⏳ 正在请求: \(currentProvider.name)"
                let requestingAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.systemBlue
                ]
                requestingItem.attributedTitle = NSAttributedString(string: requestingText, attributes: requestingAttributes)
                menu.addItem(requestingItem)
            } else if let lastProvider = proxyService.lastSuccessProvider,
                      let lastTime = proxyService.lastSuccessTime {
                let lastItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                lastItem.isEnabled = false
                let timeAgo = formatTimeAgo(lastTime)
                let lastText = "✓ 上次: \(lastProvider.name) (\(timeAgo))"
                let lastAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.systemGreen
                ]
                lastItem.attributedTitle = NSAttributedString(string: lastText, attributes: lastAttributes)
                menu.addItem(lastItem)
            }

            menu.addItem(NSMenuItem.separator())
        }

        // 添加当前提供商信息
        let currentProvider = configManager.currentProvider
        if let current = currentProvider, !configManager.proxyModeEnabled {
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

        // 添加余额信息（内联刷新图标）
        let balanceTitle = balanceStatus.menuTitle(for: currentProvider)
        let balanceItem = NSMenuItem(title: balanceTitle, action: #selector(refreshBalanceFromMenu), keyEquivalent: "")
        balanceItem.target = self
        balanceItem.isEnabled = currentProvider != nil
        let iconAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let balanceAttributes = balanceStatus.menuAttributes
        let attributed = NSMutableAttributedString(string: balanceTitle + "   ", attributes: balanceAttributes)
        attributed.append(NSAttributedString(string: "🔄", attributes: iconAttributes))
        balanceItem.attributedTitle = attributed
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

            let groupedData = configManager.providersGrouped()

            for item in groupedData {
                if let group = item.group {
                    let isCollapsed = collapsedGroups.contains(group.name)
                    let arrow = isCollapsed ? "▸" : "▾"
                    let groupItem = NSMenuItem(title: group.name, action: #selector(toggleGroup(_:)), keyEquivalent: "")
                    groupItem.target = self
                    groupItem.representedObject = group.name
                    let groupAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                        .foregroundColor: NSColor.tertiaryLabelColor
                    ]
                    groupItem.attributedTitle = NSAttributedString(string: "  \(arrow) \(group.name)", attributes: groupAttributes)
                    groupItem.toolTip = isCollapsed ? "点击展开" : "点击折叠"
                    menu.addItem(groupItem)

                    if isCollapsed {
                        continue
                    }
                }

                for provider in item.providers {
                    let indent = item.group == nil ? "  " : "      "
                    var title = provider.name
                    var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]

                    if provider.id == currentProvider?.id {
                        title = indent + "● " + title
                        attributes[.font] = NSFont.systemFont(ofSize: 13, weight: .semibold)
                        attributes[.foregroundColor] = NSColor.systemBlue

                        if let balanceInline = balanceStatus.inlineText(for: provider) {
                            title += " · \(balanceInline)"
                        }
                    } else if provider.isValid {
                        title = indent + "○ " + title
                        attributes[.foregroundColor] = NSColor.labelColor
                    } else {
                        title = indent + "⚠ " + title + " (未配置)"
                        attributes[.foregroundColor] = NSColor.tertiaryLabelColor
                    }

                    let attributedTitle = NSMutableAttributedString(string: title, attributes: attributes)

                    if configManager.isInProxyPool(provider) {
                        let penalty = proxyService.getPenalty(for: provider.id)
                        let effectivePriority = provider.priority + penalty

                        // 显示格式: [P:0 L:10] (Priority: 0, Level/Effective: 10)
                        // 使用较小的字体和次要颜色，使其不那么显眼
                        let statusText = " [P:\(provider.priority) L:\(effectivePriority)]"
                        let statusAttributes: [NSAttributedString.Key: Any] = [
                            .font: NSFont.systemFont(ofSize: 11),
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                        attributedTitle.append(NSAttributedString(string: statusText, attributes: statusAttributes))

                        // 如果有惩罚，添加额外提示
                        if penalty > 0 {
                            attributedTitle.append(NSAttributedString(string: " ⚠️", attributes: [.font: NSFont.systemFont(ofSize: 11)]))
                        }
                    }

                    let menuItem = NSMenuItem(title: title, action: #selector(selectProvider(_:)), keyEquivalent: "")
                    menuItem.target = self
                    menuItem.representedObject = provider
                    menuItem.attributedTitle = attributedTitle

                    if !provider.isValid {
                        menuItem.toolTip = "需要配置 API 密钥"
                        menuItem.isEnabled = false
                    } else if provider.id == currentProvider?.id {
                        menuItem.toolTip = "当前使用的配置"
                    } else {
                        menuItem.toolTip = "点击切换到此配置"
                    }

                    // 添加优先级详情到 tooltip
                    if configManager.isInProxyPool(provider) {
                        let penalty = proxyService.getPenalty(for: provider.id)
                        let effectivePriority = provider.priority + penalty
                        let existingTooltip = menuItem.toolTip ?? ""
                        let details = "\n\n📊 调度信息:\n基础优先级: \(provider.priority)\n惩罚值: \(penalty)\n当前调度级别: \(effectivePriority)\n(级别数值越小，调用优先级越高)"
                        menuItem.toolTip = existingTooltip + details
                    }

                    menu.addItem(menuItem)
                }
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

    /// 更新余额状态
    /// Update balance status
    func updateBalanceStatus(_ status: BalanceMenuStatus) {
        balanceStatus = status
        rebuildMenu()
    }

    // MARK: - Actions

    /// 选择提供商
    /// Select provider
    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let provider = sender.representedObject as? APIProvider else { return }

        if provider.isValid {
            configManager.setCurrentProvider(provider)
            balanceStatus = .idle
            rebuildMenu()
            showNotification(title: "已切换到: \(provider.name)")
            fetchCurrentBalance()
        } else {
            showNotification(title: "请先配置 \(provider.name) 的 API 密钥", subtitle: "点击设置菜单进行配置")
        }
    }

    /// 打开设置窗口
    /// Open settings window
    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 显示关于窗口
    /// Show about window
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

    /// 退出应用
    /// Quit application
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Observers

    /// 监听配置变更
    /// Observe configuration changes
    private func observeConfigChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configDidChange),
            name: .configDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(balanceDidUpdate(_:)),
            name: .balanceDidUpdate,
            object: nil
        )
    }

    /// 配置变更回调
    /// Configuration changed callback
    @objc private func configDidChange() {
        balanceStatus = .idle
        rebuildMenu()
        fetchCurrentBalance()
    }

    /// 监听代理服务状态
    /// Observe proxy service status
    private func observeProxyService() {
        proxyService.$isRequesting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &proxyServiceCancellables)

        proxyService.$lastSuccessProvider
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &proxyServiceCancellables)
    }

    /// 格式化时间间隔
    /// Format time ago
    /// - Parameter date: 日期 / Date
    /// - Returns: 格式化的时间描述 / Formatted time description
    private func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "\(seconds)秒前"
        } else if seconds < 3600 {
            return "\(seconds / 60)分钟前"
        } else {
            return "\(seconds / 3600)小时前"
        }
    }

    /// 切换分组折叠状态
    /// Toggle group collapse state
    @objc private func toggleGroup(_ sender: NSMenuItem) {
        guard let groupName = sender.representedObject as? String else { return }

        if collapsedGroups.contains(groupName) {
            collapsedGroups.remove(groupName)
        } else {
            collapsedGroups.insert(groupName)
        }

        saveCollapsedGroups()
        rebuildMenu()

        // 保持菜单打开
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    /// 加载折叠的分组列表
    /// Load collapsed groups list
    private func loadCollapsedGroups() {
        if let saved = UserDefaults.standard.stringArray(forKey: "collapsedGroups") {
            collapsedGroups = Set(saved)
        }
    }

    /// 保存折叠的分组列表
    /// Save collapsed groups list
    private func saveCollapsedGroups() {
        UserDefaults.standard.set(Array(collapsedGroups), forKey: "collapsedGroups")
    }

    /// 切换代理模式
    /// Toggle proxy mode
    @objc private func toggleProxyMode() {
        let newState = !configManager.proxyModeEnabled
        configManager.setProxyModeEnabled(newState)
        rebuildMenu()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    /// 余额更新回调
    /// Balance update callback
    @objc private func balanceDidUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let providerIdStr = userInfo["providerId"] as? String,
              let providerId = UUID(uuidString: providerIdStr)
        else { return }

        // 仅当更新的是当前配置时，刷新状态栏余额
        if providerId != configManager.currentProvider?.id {
            return
        }

        if let error = userInfo["error"] as? String {
            updateBalanceStatus(.failure(message: error))
            return
        }

        if let dollars = userInfo["dollars"] as? Double {
            updateBalanceStatus(.success(amount: dollars, currency: "$"))
        }
    }

    /// 从菜单刷新余额
    /// Refresh balance from menu
    @objc private func refreshBalanceFromMenu() {
        fetchCurrentBalance()

        // 尝试在点击后重新打开菜单，避免菜单被关闭
        // Try to reopen menu after click to avoid menu closing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    /// 获取当前提供商余额
    /// Fetch current provider balance
    private func fetchCurrentBalance() {
        guard let provider = configManager.currentProvider, provider.isValid else {
            updateBalanceStatus(.failure(message: "请选择有效配置"))
            return
        }

        updateBalanceStatus(.loading)

        let tokensPerDollar = 500_000.0
        balanceService.fetchBalance(for: provider) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let balance):
                    let dollars = Double(balance.availableTokens) / tokensPerDollar
                    self.updateBalanceStatus(.success(amount: dollars, currency: "$"))
                case .failure(let error):
                    self.updateBalanceStatus(.failure(message: error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Notifications

    /// 请求通知权限
    /// Request notification permission
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("通知权限请求失败: \(error)")
            }
        }
    }

    /// 显示通知
    /// Show notification
    /// - Parameters:
    ///   - title: 标题 / Title
    ///   - subtitle: 副标题 / Subtitle
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

// MARK: - Balance Menu Status 余额菜单状态

/// 菜单中的余额显示状态
/// Balance display status in menu
enum BalanceMenuStatus {
    /// 空闲状态
    /// Idle state
    case idle

    /// 加载中
    /// Loading
    case loading

    /// 成功
    /// Success with amount and currency
    case success(amount: Double, currency: String)

    /// 失败
    /// Failure with error message
    case failure(message: String)

    /// 菜单标题
    /// Menu title
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
            return "⚠️ 余额：--"
        }
    }

    /// 内联文本（显示在提供商名称旁边）
    /// Inline text for display next to provider name
    func inlineText(for provider: APIProvider?) -> String? {
        guard provider != nil else { return nil }

        switch self {
        case .idle:
            return nil
        case .loading:
            return "查询中..."
        case .success(let amount, let currency):
            let amountText = "\(currency)\(String(format: "%.2f", amount))"
            return amountText
        case .failure:
            return "⚠️"
        }
    }

    /// 菜单属性（字体、颜色等）
    /// Menu attributes (font, color, etc.)
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

    /// 工具提示文本
    /// Tooltip text
    func tooltip(for provider: APIProvider?) -> String {
        switch self {
        case .idle:
            return provider == nil ? "选择配置后可查询余额" : "点击刷新余额"
        case .loading:
            return "正在查询余额..."
        case .success(let amount, _):
            return amount < 5.0 ? "余额低于 $5，建议尽快充值\n点击刷新" : "余额状态正常\n点击刷新"
        case .failure(let message):
            return "获取失败：\(message)\n点击重试"
        }
    }
}
