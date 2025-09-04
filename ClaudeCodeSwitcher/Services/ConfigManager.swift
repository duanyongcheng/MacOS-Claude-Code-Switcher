import Foundation
import Combine
import AppKit

// MARK: - App Configuration Model
struct AppConfig: Codable {
    let providers: [APIProvider]
    let currentProvider: APIProvider?
    let autoUpdate: Bool
    let proxyHost: String
    let proxyPort: String
    let autoStartup: Bool
    
    enum CodingKeys: String, CodingKey {
        case providers, currentProvider, autoUpdate, proxyHost, proxyPort, autoStartup
    }
    
    // 自定义解码，处理旧配置文件中没有 autoStartup 的情况
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.providers = try container.decode([APIProvider].self, forKey: .providers)
        self.currentProvider = try container.decodeIfPresent(APIProvider.self, forKey: .currentProvider)
        self.autoUpdate = try container.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? true
        self.proxyHost = try container.decodeIfPresent(String.self, forKey: .proxyHost) ?? ""
        self.proxyPort = try container.decodeIfPresent(String.self, forKey: .proxyPort) ?? ""
        self.autoStartup = try container.decodeIfPresent(Bool.self, forKey: .autoStartup) ?? false
    }
    
    // 自定义编码
    init(providers: [APIProvider], currentProvider: APIProvider?, autoUpdate: Bool, proxyHost: String, proxyPort: String, autoStartup: Bool) {
        self.providers = providers
        self.currentProvider = currentProvider
        self.autoUpdate = autoUpdate
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.autoStartup = autoStartup
    }
}

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var providers: [APIProvider] = []
    @Published var currentProvider: APIProvider?
    @Published var autoUpdate: Bool = true
    @Published var proxyHost: String = ""
    @Published var proxyPort: String = ""
    @Published var autoStartup: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let claudeConfigPath: URL
    private let appConfigPath: URL
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        claudeConfigPath = homeDir.appendingPathComponent(".claude/settings.json")
        appConfigPath = homeDir.appendingPathComponent(".config/ccs/claude-switch.json")
        loadConfiguration()
    }
    
    // MARK: - Public Methods
    
    func getProviders() -> [APIProvider] {
        return providers
    }
    
    func addProvider(_ provider: APIProvider) {
        print("添加新提供商: \(provider.name)")
        providers.append(provider)
        print("当前提供商列表: \(providers.map { $0.name })")
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
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
            postConfigChangeNotification()
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
        postConfigChangeNotification()
    }
    
    func setCurrentProvider(_ provider: APIProvider) {
        currentProvider = provider
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }
    
    func copyProvider(_ provider: APIProvider) {
        let copiedProvider = APIProvider(
            name: provider.name + "-复制",
            url: provider.url,
            key: provider.key,
            largeModel: provider.largeModel,
            smallModel: provider.smallModel
        )
        providers.append(copiedProvider)
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }
    
    func updateGlobalSettings(autoUpdate: Bool, proxyHost: String, proxyPort: String, autoStartup: Bool) {
        self.autoUpdate = autoUpdate
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        
        // 更新开机自启动设置
        let wasAutoStartup = self.autoStartup
        self.autoStartup = autoStartup
        
        if wasAutoStartup != autoStartup {
            updateLaunchAgentStatus(autoStartup)
        } else if autoStartup {
            // 如果开机自启已启用但状态不正确，重新安装
            if !checkLaunchAgentStatus() {
                print("检测到 Launch Agent 状态不正确，重新安装...")
                updateLaunchAgentStatus(true)
            }
        }
        
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }
    
    // MARK: - Private Methods
    
    // MARK: - File Management
    
    private func ensureConfigDirectoryExists() throws {
        let configDir = appConfigPath.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: configDir.path) {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        }
    }
    
    private func atomicWrite(to url: URL, data: Data) throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString)
        
        // 写入临时文件
        try data.write(to: tempFile)
        
        // 如果目标文件存在，先删除
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        
        // 原子性替换
        try FileManager.default.moveItem(at: tempFile, to: url)
    }
    
    private func loadConfigFromFile() throws -> AppConfig? {
        guard FileManager.default.fileExists(atPath: appConfigPath.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: appConfigPath)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }
    
    private func saveConfigToFile(_ config: AppConfig) throws {
        try ensureConfigDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try atomicWrite(to: appConfigPath, data: data)
        
        // 设置文件权限为仅用户可读写
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: appConfigPath.path)
    }
    
    private func migrateFromUserDefaults() throws {
        // 检查是否有 UserDefaults 配置
        guard userDefaults.data(forKey: "providers") != nil else {
            return // 没有需要迁移的配置
        }
        
        print("发现 UserDefaults 配置，开始迁移到 JSON 文件...")
        
        // 从 UserDefaults 读取配置
        var providers: [APIProvider] = []
        var currentProvider: APIProvider?
        let autoUpdate = userDefaults.bool(forKey: "autoUpdate")
        let proxyHost = userDefaults.string(forKey: "proxyHost") ?? ""
        let proxyPort = userDefaults.string(forKey: "proxyPort") ?? ""
        let autoStartup = userDefaults.bool(forKey: "autoStartup")
        
        if let data = userDefaults.data(forKey: "providers"),
           let decodedProviders = try? JSONDecoder().decode([APIProvider].self, from: data) {
            providers = decodedProviders
        }
        
        if let data = userDefaults.data(forKey: "currentProvider"),
           let decodedProvider = try? JSONDecoder().decode(APIProvider.self, from: data) {
            currentProvider = decodedProvider
        }
        
        // 创建配置对象
        let config = AppConfig(
            providers: providers,
            currentProvider: currentProvider,
            autoUpdate: autoUpdate,
            proxyHost: proxyHost,
            proxyPort: proxyPort,
            autoStartup: autoStartup
        )
        
        // 保存到文件
        try saveConfigToFile(config)
        
        // 清理 UserDefaults
        userDefaults.removeObject(forKey: "providers")
        userDefaults.removeObject(forKey: "currentProvider")
        userDefaults.removeObject(forKey: "autoUpdate")
        userDefaults.removeObject(forKey: "proxyHost")
        userDefaults.removeObject(forKey: "proxyPort")
        userDefaults.removeObject(forKey: "autoStartup")
        
        print("配置迁移完成")
    }
    
    private func loadConfiguration() {
        // 首先尝试从文件加载配置
        if let config = try? loadConfigFromFile() {
            providers = config.providers
            currentProvider = config.currentProvider
            autoUpdate = config.autoUpdate
            proxyHost = config.proxyHost
            proxyPort = config.proxyPort
            autoStartup = config.autoStartup
            print("从配置文件加载配置成功")
            return
        }
        
        // 如果文件不存在，尝试从 UserDefaults 迁移
        do {
            try migrateFromUserDefaults()
            // 迁移后重新加载
            if let config = try? loadConfigFromFile() {
                providers = config.providers
                currentProvider = config.currentProvider
                autoUpdate = config.autoUpdate
                proxyHost = config.proxyHost
                proxyPort = config.proxyPort
                autoStartup = config.autoStartup
                print("从 UserDefaults 迁移配置成功")
            }
        } catch {
            print("迁移配置失败，使用默认配置: \(error)")
            // 使用默认配置
            providers = []
            currentProvider = nil
            autoUpdate = true
            proxyHost = ""
            proxyPort = ""
            autoStartup = false
        }
    }
    
    private func saveConfiguration() {
        print("开始保存配置...")
        print("提供商数量: \(providers.count)")
        print("提供商列表: \(providers.map { "\($0.name) (ID: \($0.id))" })")
        
        // 创建配置对象
        let config = AppConfig(
            providers: providers,
            currentProvider: currentProvider,
            autoUpdate: autoUpdate,
            proxyHost: proxyHost,
            proxyPort: proxyPort,
            autoStartup: autoStartup
        )
        
        // 保存到文件
        do {
            try saveConfigToFile(config)
            print("配置保存到文件成功: \(appConfigPath.path)")
            
            // 验证保存的内容
            if let savedData = try? Data(contentsOf: appConfigPath),
               let savedConfig = try? JSONDecoder().decode(AppConfig.self, from: savedData) {
                print("验证: 已保存 \(savedConfig.providers.count) 个提供商")
            }
        } catch {
            print("保存配置到文件失败: \(error)")
            // 如果文件保存失败，尝试保存到 UserDefaults 作为备用
            saveToUserDefaultsFallback()
        }
    }
    
    private func saveToUserDefaultsFallback() {
        // 备用方案：保存到 UserDefaults
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
        
        print("配置已保存到 UserDefaults 备用")
    }
    
    private func syncToClaudeConfig() {
        do {
            // 确保 .claude 目录存在
            let claudeDir = claudeConfigPath.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: claudeDir.path) {
                try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            }
            
            // 使用 ClaudeConfig 模型来管理配置
            var claudeConfig: ClaudeConfig
            
            // 读取现有配置
            if FileManager.default.fileExists(atPath: claudeConfigPath.path) {
                let data = try Data(contentsOf: claudeConfigPath)
                claudeConfig = try JSONDecoder().decode(ClaudeConfig.self, from: data)
            } else {
                claudeConfig = ClaudeConfig()
            }
            
            // 更新 Switcher 管理的字段
            updateSwitcherManagedFields(&claudeConfig)
            
            // 写入配置文件
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(claudeConfig)
            try data.write(to: claudeConfigPath)
            
            print("已同步配置到 Claude 配置文件: \(claudeConfigPath.path)")
            
        } catch {
            print("同步 Claude 配置失败: \(error)")
        }
    }
    
    private func updateSwitcherManagedFields(_ config: inout ClaudeConfig) {
        // 确保 env 对象存在
        if config.env == nil {
            config.env = ClaudeConfig.Environment()
        }
        
        // 只更新 Switcher 管理的字段
        if let provider = currentProvider {
            config.env?.ANTHROPIC_API_KEY = provider.key
            config.env?.ANTHROPIC_BASE_URL = provider.url
            
            // 可选字段：只在有值时设置，否则移除
            if let largeModel = provider.largeModel, !largeModel.isEmpty {
                config.env?.ANTHROPIC_MODEL = largeModel
            } else {
                config.env?.ANTHROPIC_MODEL = nil
            }
            
            if let smallModel = provider.smallModel, !smallModel.isEmpty {
                config.env?.ANTHROPIC_SMALL_FAST_MODEL = smallModel
            } else {
                config.env?.ANTHROPIC_SMALL_FAST_MODEL = nil
            }
        } else {
            // 没有当前提供商时，清空这些字段
            config.env?.ANTHROPIC_API_KEY = ""
            config.env?.ANTHROPIC_BASE_URL = ""
            config.env?.ANTHROPIC_MODEL = nil
            config.env?.ANTHROPIC_SMALL_FAST_MODEL = nil
        }
        
        // 处理代理设置
        let proxyUrl = buildProxyUrl()
        if !proxyUrl.isEmpty {
            config.env?.HTTPS_PROXY = proxyUrl
            config.env?.HTTP_PROXY = proxyUrl
        } else {
            config.env?.HTTPS_PROXY = nil
            config.env?.HTTP_PROXY = nil
        }
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
    
    // MARK: - Launch Agent Management
    
    private func updateLaunchAgentStatus(_ shouldAutoStart: Bool) {
        if shouldAutoStart {
            installLaunchAgent()
        } else {
            removeLaunchAgent()
        }
    }
    
    // 检查开机自启状态
    func checkLaunchAgentStatus() -> Bool {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.example.ClaudeCodeSwitcher"
        let plistPath = launchAgentsDir.appendingPathComponent("\(bundleIdentifier).plist")
        
        // 检查 plist 文件是否存在
        guard FileManager.default.fileExists(atPath: plistPath.path) else {
            return false
        }
        
        // 检查 launchctl 是否已加载
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list", bundleIdentifier]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.launch()
        task.waitUntilExit()
        
        return task.terminationStatus == 0
    }
    
    private func installLaunchAgent() {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        
        // 使用正确的 bundle identifier，避免硬编码
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.example.ClaudeCodeSwitcher"
        let plistPath = launchAgentsDir.appendingPathComponent("\(bundleIdentifier).plist")
        
        print("正在安装 Launch Agent...")
        print("Bundle Identifier: \(bundleIdentifier)")
        print("Plist 路径: \(plistPath.path)")
        
        // 确保 LaunchAgents 目录存在
        do {
            try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            print("LaunchAgents 目录创建成功")
        } catch {
            print("创建 LaunchAgents 目录失败: \(error)")
            return
        }
        
        // 获取应用程序路径和可执行文件名称
        guard let bundlePath = Bundle.main.bundlePath as String? else {
            print("无法获取应用程序路径")
            return
        }
        
        guard let executableName = Bundle.main.executablePath?.components(separatedBy: "/").last else {
            print("无法获取可执行文件名称")
            return
        }
        
        let executablePath = "\(bundlePath)/Contents/MacOS/\(executableName)"
        
        print("应用路径: \(bundlePath)")
        print("可执行文件路径: \(executablePath)")
        print("可执行文件名称: \(executableName)")
        
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(bundleIdentifier)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>LSUIElement</key>
            <true/>
            <key>WorkingDirectory</key>
            <string>\(bundlePath)</string>
        </dict>
        </plist>
        """
        
        do {
            try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
            print("Launch Agent plist 文件写入成功: \(plistPath.path)")
            
            // 验证文件是否真的写入了
            if FileManager.default.fileExists(atPath: plistPath.path) {
                print("Plist 文件验证成功")
            } else {
                print("Plist 文件验证失败 - 文件不存在")
                return
            }
            
            // 先卸载旧的 Launch Agent（如果存在）
            print("正在卸载旧的 Launch Agent...")
            let unloadTask = Process()
            unloadTask.launchPath = "/bin/launchctl"
            unloadTask.arguments = ["unload", plistPath.path]
            unloadTask.launch()
            unloadTask.waitUntilExit()
            print("卸载操作完成，退出码: \(unloadTask.terminationStatus)")
            
            // 加载新的 Launch Agent
            print("正在加载新的 Launch Agent...")
            let loadTask = Process()
            loadTask.launchPath = "/bin/launchctl"
            loadTask.arguments = ["load", plistPath.path]
            loadTask.launch()
            loadTask.waitUntilExit()
            
            if loadTask.terminationStatus == 0 {
                print("Launch Agent 加载成功")
                
                // 验证是否真的加载了
                let verifyTask = Process()
                verifyTask.launchPath = "/bin/launchctl"
                verifyTask.arguments = ["list", bundleIdentifier]
                verifyTask.launch()
                verifyTask.waitUntilExit()
                
                if verifyTask.terminationStatus == 0 {
                    print("Launch Agent 验证成功 - 已在 launchctl 列表中")
                } else {
                    print("Launch Agent 验证失败 - 不在 launchctl 列表中")
                }
                
            } else {
                print("Launch Agent 加载失败，退出码: \(loadTask.terminationStatus)")
                
                // 获取错误输出
                let errorTask = Process()
                errorTask.launchPath = "/bin/launchctl"
                errorTask.arguments = ["load", plistPath.path]
                let errorPipe = Pipe()
                errorTask.standardError = errorPipe
                errorTask.launch()
                errorTask.waitUntilExit()
                
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorMessage = String(data: errorData, encoding: .utf8) {
                    print("Launch Agent 错误信息: \(errorMessage)")
                }
            }
            
        } catch {
            print("Launch Agent 安装失败: \(error)")
        }
    }
    
    private func removeLaunchAgent() {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        
        // 使用与安装时相同的 bundle identifier
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.example.ClaudeCodeSwitcher"
        let plistPath = launchAgentsDir.appendingPathComponent("\(bundleIdentifier).plist")
        
        // 卸载 Launch Agent
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", plistPath.path]
        task.launch()
        task.waitUntilExit()
        
        // 删除 plist 文件
        do {
            try FileManager.default.removeItem(at: plistPath)
            print("Launch Agent 移除成功")
        } catch {
            print("Launch Agent 移除失败: \(error)")
        }
        
        // 同时清理旧的 plist 文件（如果存在）
        let oldPlistPath = launchAgentsDir.appendingPathComponent("com.example.ClaudeCodeSwitcher.plist")
        if FileManager.default.fileExists(atPath: oldPlistPath.path) {
            do {
                try FileManager.default.removeItem(at: oldPlistPath)
                print("已清理旧的 Launch Agent 文件")
            } catch {
                print("清理旧 Launch Agent 文件失败: \(error)")
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let configDidChange = Notification.Name("configDidChange")
}
