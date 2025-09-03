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
}

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var providers: [APIProvider] = []
    @Published var currentProvider: APIProvider?
    @Published var autoUpdate: Bool = true
    @Published var proxyHost: String = ""
    @Published var proxyPort: String = ""
    
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
        providers.append(provider)
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
    
    func updateGlobalSettings(autoUpdate: Bool, proxyHost: String, proxyPort: String) {
        self.autoUpdate = autoUpdate
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
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
        let data = try JSONEncoder().encode(config)
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
            proxyPort: proxyPort
        )
        
        // 保存到文件
        try saveConfigToFile(config)
        
        // 清理 UserDefaults
        userDefaults.removeObject(forKey: "providers")
        userDefaults.removeObject(forKey: "currentProvider")
        userDefaults.removeObject(forKey: "autoUpdate")
        userDefaults.removeObject(forKey: "proxyHost")
        userDefaults.removeObject(forKey: "proxyPort")
        
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
        }
    }
    
    private func saveConfiguration() {
        // 创建配置对象
        let config = AppConfig(
            providers: providers,
            currentProvider: currentProvider,
            autoUpdate: autoUpdate,
            proxyHost: proxyHost,
            proxyPort: proxyPort
        )
        
        // 保存到文件
        do {
            try saveConfigToFile(config)
            print("配置保存到文件成功")
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
            
            // 读取现有配置作为原始 JSON（保留所有字段）
            var existingJson: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: claudeConfigPath.path) {
                let data = try Data(contentsOf: claudeConfigPath)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    existingJson = json
                }
            }
            
            // 更新仅由 Switcher 管理的字段
            updateSwitcherManagedFields(&existingJson)
            
            // 写入配置文件
            let data = try JSONSerialization.data(withJSONObject: existingJson, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: claudeConfigPath)
            
            print("已同步配置到 Claude 配置文件: \(claudeConfigPath.path)")
            
        } catch {
            print("同步 Claude 配置失败: \(error)")
        }
    }
    
    private func updateSwitcherManagedFields(_ json: inout [String: Any]) {
        // 确保 env 对象存在
        var env = (json["env"] as? [String: Any]) ?? [:]
        
        // 只更新 Switcher 管理的字段
        if let provider = currentProvider {
            env["ANTHROPIC_API_KEY"] = provider.key
            env["ANTHROPIC_BASE_URL"] = provider.url
            
            // 可选字段：只在有值时设置，否则移除
            if let largeModel = provider.largeModel, !largeModel.isEmpty {
                env["ANTHROPIC_MODEL"] = largeModel
            } else {
                env.removeValue(forKey: "ANTHROPIC_MODEL")
            }
            
            if let smallModel = provider.smallModel, !smallModel.isEmpty {
                env["ANTHROPIC_SMALL_FAST_MODEL"] = smallModel
            } else {
                env.removeValue(forKey: "ANTHROPIC_SMALL_FAST_MODEL")
            }
        } else {
            // 没有当前提供商时，清空这些字段
            env["ANTHROPIC_API_KEY"] = ""
            env["ANTHROPIC_BASE_URL"] = ""
            env.removeValue(forKey: "ANTHROPIC_MODEL")
            env.removeValue(forKey: "ANTHROPIC_SMALL_FAST_MODEL")
        }
        
        // 处理代理设置
        let proxyUrl = buildProxyUrl()
        if !proxyUrl.isEmpty {
            env["HTTPS_PROXY"] = proxyUrl
            env["HTTP_PROXY"] = proxyUrl
        } else {
            env.removeValue(forKey: "HTTPS_PROXY")
            env.removeValue(forKey: "HTTP_PROXY")
        }
        
        // 更新 env 对象
        json["env"] = env
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