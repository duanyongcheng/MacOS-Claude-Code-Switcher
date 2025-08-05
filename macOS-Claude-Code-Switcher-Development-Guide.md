# Claude Code Switcher for macOS - Swift 开发文档

基于原 GNOME Shell 扩展功能，为 macOS 开发一个状态栏应用来管理 Claude Code API 提供商配置。

## 项目概述

### 功能需求
- 在 macOS 状态栏显示 Claude Code 切换图标
- 提供下拉菜单显示可用的 API 提供商
- 支持添加、编辑、删除自定义 API 提供商
- 实时同步配置到 `~/.claude/settings.json`
- 支持代理设置和自动更新控制
- 提供设置窗口进行详细配置

### 技术栈
- **Swift** - 主要开发语言
- **AppKit** - macOS 原生 UI 框架
- **NSStatusBar** - 状态栏集成
- **UserDefaults** - 本地配置存储
- **Codable** - JSON 序列化/反序列化

## 项目架构

### 核心组件

```
ClaudeCodeSwitcher/
├── App/
│   ├── AppDelegate.swift          # 应用主入口
│   ├── StatusBarController.swift  # 状态栏控制器
│   └── SettingsWindowController.swift # 设置窗口控制器
├── Models/
│   ├── APIProvider.swift          # API 提供商数据模型
│   └── ClaudeConfig.swift         # Claude 配置模型
├── Services/
│   ├── ConfigManager.swift        # 配置管理服务
│   └── FileManager+Extension.swift # 文件操作扩展
├── Views/
│   ├── StatusBarMenu.swift        # 状态栏菜单
│   └── SettingsView.swift         # 设置界面
└── Resources/
    ├── Assets.xcassets            # 图标资源
    └── Info.plist                 # 应用配置
```

## 数据模型设计

### APIProvider 模型

```swift
import Foundation

struct APIProvider: Codable, Identifiable, Equatable {
    let id = UUID()
    var name: String
    var url: String
    var key: String
    var largeModel: String?
    var smallModel: String?
    
    enum CodingKeys: String, CodingKey {
        case name, url, key, largeModel, smallModel
    }
    
    init(name: String, url: String, key: String, largeModel: String? = nil, smallModel: String? = nil) {
        self.name = name
        self.url = url
        self.key = key
        self.largeModel = largeModel
        self.smallModel = smallModel
    }
    
    // 验证 API 密钥是否配置
    var isValid: Bool {
        return !name.isEmpty && !url.isEmpty && !key.isEmpty
    }
}
```

### ClaudeConfig 模型

```swift
import Foundation

struct ClaudeConfig: Codable {
    var env: ClaudeEnvironment
    var permissions: ClaudePermissions?
    var feedbackSurveyState: FeedbackSurveyState?
    
    struct ClaudeEnvironment: Codable {
        var ANTHROPIC_AUTH_TOKEN: String
        var ANTHROPIC_BASE_URL: String
        var ANTHROPIC_MODEL: String
        var ANTHROPIC_SMALL_FAST_MODEL: String
        var DISABLE_AUTOUPDATER: String
        var HTTPS_PROXY: String
        var HTTP_PROXY: String
    }
    
    struct ClaudePermissions: Codable {
        var allow: [String]
        var deny: [String]
    }
    
    struct FeedbackSurveyState: Codable {
        var lastShownTime: TimeInterval
    }
}
```

## 核心实现

### 1. AppDelegate - 应用主入口

```swift
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupApplication()
        statusBarController = StatusBarController()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // 清理资源
    }
    
    private func setupApplication() {
        // 隐藏 Dock 图标（仅状态栏运行）
        NSApp.setActivationPolicy(.accessory)
    }
}
```

### 2. StatusBarController - 状态栏控制器

```swift
import Cocoa

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var configManager: ConfigManager!
    private var settingsWindowController: SettingsWindowController?
    
    override init() {
        super.init()
        configManager = ConfigManager.shared
        setupStatusBar()
        setupMenu()
        observeConfigChanges()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Claude Code Switcher")
            button.image?.isTemplate = true
        }
    }
    
    private func setupMenu() {
        menu = NSMenu()
        statusItem.menu = menu
        rebuildMenu()
    }
    
    private func rebuildMenu() {
        menu.removeAllItems()
        
        // 添加 API 提供商列表
        let providers = configManager.getProviders()
        let currentProvider = configManager.currentProvider
        
        if providers.isEmpty {
            let noProvidersItem = NSMenuItem(title: "暂无配置的提供商", action: nil, keyEquivalent: "")
            noProvidersItem.isEnabled = false
            menu.addItem(noProvidersItem)
        } else {
            for provider in providers {
                let item = NSMenuItem(title: provider.name, action: #selector(selectProvider(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = provider
                
                // 标记当前选中的提供商
                if provider.name == currentProvider?.name {
                    item.state = .on
                }
                
                // 检查 API 密钥是否配置
                if !provider.isValid {
                    item.isEnabled = false
                }
                
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 添加设置菜单项
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // 添加退出菜单项
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
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
    
    private func showNotification(title: String, subtitle: String? = nil) {
        let notification = NSUserNotification()
        notification.title = title
        notification.subtitle = subtitle
        NSUserNotificationCenter.default.deliver(notification)
    }
}
```

### 3. ConfigManager - 配置管理服务

```swift
import Foundation

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var providers: [APIProvider] = []
    @Published var currentProvider: APIProvider?
    @Published var autoUpdate: Bool = true
    @Published var proxyHost: String = ""
    @Published var proxyPort: String = ""
    
    private let userDefaults = UserDefaults.standard
    private let claudeConfigPath: URL
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        claudeConfigPath = homeDir.appendingPathComponent(".claude/settings.json")
        loadConfiguration()
    }
    
    // MARK: - Public Methods
    
    func getProviders() -> [APIProvider] {
        return providers
    }
    
    func addProvider(_ provider: APIProvider) {
        providers.append(provider)
        saveConfiguration()
        syncToClaudeConfig()
    }
    
    func updateProvider(_ provider: APIProvider) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
            
            // 如果更新的是当前提供商，也要更新当前提供商
            if currentProvider?.id == provider.id {
                currentProvider = provider
            }
            
            saveConfiguration()
            syncToClaudeConfig()
        }
    }
    
    func removeProvider(_ provider: APIProvider) {
        providers.removeAll { $0.id == provider.id }
        
        // 如果删除的是当前提供商，清空当前提供商
        if currentProvider?.id == provider.id {
            currentProvider = nil
        }
        
        saveConfiguration()
        syncToClaudeConfig()
    }
    
    func setCurrentProvider(_ provider: APIProvider) {
        currentProvider = provider
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }
    
    func updateGlobalSettings(autoUpdate: Bool, proxyHost: String, proxyPort: String) {
        self.autoUpdate = autoUpdate
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        saveConfiguration()
        syncToClaudeConfig()
    }
    
    // MARK: - Private Methods
    
    private func loadConfiguration() {
        // 从 UserDefaults 加载配置
        if let data = userDefaults.data(forKey: "providers"),
           let decodedProviders = try? JSONDecoder().decode([APIProvider].self, from: data) {
            providers = decodedProviders
        }
        
        if let data = userDefaults.data(forKey: "currentProvider"),
           let decodedProvider = try? JSONDecoder().decode(APIProvider.self, from: data) {
            currentProvider = decodedProvider
        }
        
        autoUpdate = userDefaults.bool(forKey: "autoUpdate")
        proxyHost = userDefaults.string(forKey: "proxyHost") ?? ""
        proxyPort = userDefaults.string(forKey: "proxyPort") ?? ""
    }
    
    private func saveConfiguration() {
        // 保存到 UserDefaults
        if let data = try? JSONEncoder().encode(providers) {
            userDefaults.set(data, forKey: "providers")
        }
        
        if let currentProvider = currentProvider,
           let data = try? JSONEncoder().encode(currentProvider) {
            userDefaults.set(data, forKey: "currentProvider")
        } else {
            userDefaults.removeObject(forKey: "currentProvider")
        }
        
        userDefaults.set(autoUpdate, forKey: "autoUpdate")
        userDefaults.set(proxyHost, forKey: "proxyHost")
        userDefaults.set(proxyPort, forKey: "proxyPort")
    }
    
    private func syncToClaudeConfig() {
        do {
            // 确保 .claude 目录存在
            let claudeDir = claudeConfigPath.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: claudeDir.path) {
                try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            }
            
            // 读取现有配置（如果存在）
            var existingConfig: ClaudeConfig?
            if FileManager.default.fileExists(atPath: claudeConfigPath.path) {
                let data = try Data(contentsOf: claudeConfigPath)
                existingConfig = try JSONDecoder().decode(ClaudeConfig.self, from: data)
            }
            
            // 构建新配置
            let config = buildClaudeConfig(existing: existingConfig)
            
            // 写入配置文件
            let data = try JSONEncoder().encode(config)
            try data.write(to: claudeConfigPath)
            
            print("已同步配置到 Claude 配置文件: \(claudeConfigPath.path)")
            
        } catch {
            print("同步 Claude 配置失败: \(error)")
        }
    }
    
    private func buildClaudeConfig(existing: ClaudeConfig?) -> ClaudeConfig {
        let proxyUrl = buildProxyUrl()
        
        let env = ClaudeConfig.ClaudeEnvironment(
            ANTHROPIC_AUTH_TOKEN: currentProvider?.key ?? "",
            ANTHROPIC_BASE_URL: currentProvider?.url ?? "",
            ANTHROPIC_MODEL: currentProvider?.largeModel ?? "",
            ANTHROPIC_SMALL_FAST_MODEL: currentProvider?.smallModel ?? "",
            DISABLE_AUTOUPDATER: autoUpdate ? "0" : "1",
            HTTPS_PROXY: proxyUrl,
            HTTP_PROXY: proxyUrl
        )
        
        return ClaudeConfig(
            env: env,
            permissions: existing?.permissions ?? ClaudeConfig.ClaudePermissions(allow: [], deny: []),
            feedbackSurveyState: existing?.feedbackSurveyState ?? ClaudeConfig.FeedbackSurveyState(lastShownTime: Date().timeIntervalSince1970)
        )
    }
    
    private func buildProxyUrl() -> String {
        guard !proxyHost.isEmpty else { return "" }
        
        let host = proxyHost
        let port = proxyPort.isEmpty ? "" : ":\(proxyPort)"
        let url = "\(host)\(port)"
        
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return url
        } else {
            return "http://\(url)"
        }
    }
    
    private func postConfigChangeNotification() {
        NotificationCenter.default.post(name: .configDidChange, object: nil)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let configDidChange = Notification.Name("configDidChange")
}
```

### 4. SettingsWindowController - 设置窗口

```swift
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
```

### 5. SettingsView - SwiftUI 设置界面

```swift
import SwiftUI

struct SettingsView: View {
    @StateObject private var configManager = ConfigManager.shared
    @State private var showingAddProvider = false
    @State private var editingProvider: APIProvider?
    
    var body: some View {
        TabView {
            // API 提供商标签页
            ProvidersView(
                providers: configManager.providers,
                currentProvider: configManager.currentProvider,
                showingAddProvider: $showingAddProvider,
                editingProvider: $editingProvider
            )
            .tabItem {
                Label("API 提供商", systemImage: "server.rack")
            }
            
            // 全局设置标签页
            GlobalSettingsView(
                autoUpdate: $configManager.autoUpdate,
                proxyHost: $configManager.proxyHost,
                proxyPort: $configManager.proxyPort
            )
            .tabItem {
                Label("全局设置", systemImage: "gearshape")
            }
            
            // 关于标签页
            AboutView()
            .tabItem {
                Label("关于", systemImage: "info.circle")
            }
        }
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showingAddProvider) {
            AddProviderView { provider in
                configManager.addProvider(provider)
            }
        }
        .sheet(item: $editingProvider) { provider in
            EditProviderView(provider: provider) { updatedProvider in
                configManager.updateProvider(updatedProvider)
            }
        }
    }
}

struct ProvidersView: View {
    let providers: [APIProvider]
    let currentProvider: APIProvider?
    @Binding var showingAddProvider: Bool
    @Binding var editingProvider: APIProvider?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("API 提供商")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                Button("添加提供商") {
                    showingAddProvider = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            if providers.isEmpty {
                Text("暂无配置的提供商")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(providers) { provider in
                        ProviderRow(
                            provider: provider,
                            isCurrent: provider.id == currentProvider?.id
                        ) { provider in
                            editingProvider = provider
                        } onDelete: { provider in
                            ConfigManager.shared.removeProvider(provider)
                        } onSelect: { provider in
                            ConfigManager.shared.setCurrentProvider(provider)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct ProviderRow: View {
    let provider: APIProvider
    let isCurrent: Bool
    let onEdit: (APIProvider) -> Void
    let onDelete: (APIProvider) -> Void
    let onSelect: (APIProvider) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(provider.name)
                        .font(.headline)
                    
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    if !provider.isValid {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
                
                Text(provider.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button("选择") {
                    onSelect(provider)
                }
                .disabled(!provider.isValid || isCurrent)
                
                Button("编辑") {
                    onEdit(provider)
                }
                
                Button("删除") {
                    onDelete(provider)
                }
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

struct GlobalSettingsView: View {
    @Binding var autoUpdate: Bool
    @Binding var proxyHost: String
    @Binding var proxyPort: String
    
    var body: some View {
        Form {
            Section("更新设置") {
                Toggle("自动更新", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, newValue in
                        ConfigManager.shared.updateGlobalSettings(
                            autoUpdate: newValue,
                            proxyHost: proxyHost,
                            proxyPort: proxyPort
                        )
                    }
            }
            
            Section("代理设置") {
                TextField("代理服务器", text: $proxyHost)
                TextField("端口", text: $proxyPort)
                
                Button("保存代理设置") {
                    ConfigManager.shared.updateGlobalSettings(
                        autoUpdate: autoUpdate,
                        proxyHost: proxyHost,
                        proxyPort: proxyPort
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Claude Code Switcher")
                .font(.title)
                .bold()
            
            Text("快速切换 Claude Code API 提供商")
                .font(.subtitle)
                .foregroundColor(.secondary)
            
            Text("版本 1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

## 开发步骤

### 1. 创建 Xcode 项目

```bash
# 创建新的 macOS App 项目
# Target: macOS
# Interface: SwiftUI
# Language: Swift
```

### 2. 配置项目设置

在 `Info.plist` 中添加：

```xml
<key>LSUIElement</key>
<true/>
<!-- 设置为后台应用，不显示在 Dock 中 -->

<key>NSUserNotificationAlertStyle</key>
<string>alert</string>
<!-- 允许发送通知 -->
```

### 3. 添加必要权限

在项目的 `Signing & Capabilities` 中添加：
- App Sandbox (如果需要上架 App Store)
- User Selected File (读写 ~/.claude 目录)

### 4. 构建和测试

```bash
# 编译项目
cmd + R

# 检查状态栏是否正常显示
# 测试菜单交互
# 验证配置文件同步功能
```

## 部署考虑

### 1. 代码签名
```bash
# 为发布版本配置代码签名
codesign --force --deep --sign "Developer ID Application: Your Name" ClaudeCodeSwitcher.app
```

### 2. 公证（Notarization）
```bash
# 上传到 Apple 进行公证
xcrun notarytool submit ClaudeCodeSwitcher.app.zip --keychain-profile "notary-profile"
```

### 3. 分发
- 直接分发 .app 文件
- 打包为 .dmg 安装包
- 通过 Mac App Store 分发

## 扩展功能建议

1. **快捷键支持** - 添加全局快捷键快速切换提供商
2. **配置导入导出** - 支持配置文件的备份和恢复
3. **使用统计** - 记录每个提供商的使用频率
4. **API 状态检测** - 定期检查 API 端点的可用性
5. **主题定制** - 支持浅色/深色主题切换

这个 Swift 实现保持了原 GNOME Shell 扩展的核心功能，同时充分利用了 macOS 的原生特性和 SwiftUI 的现代界面设计。