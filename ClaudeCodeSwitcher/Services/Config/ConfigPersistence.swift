import Foundation

// MARK: - App Configuration Model 应用配置模型

/// 应用配置数据模型
/// Application configuration data model
struct AppConfig: Codable {
    let providers: [APIProvider]
    let currentProvider: APIProvider?
    let autoUpdate: Bool
    let proxyHost: String
    let proxyPort: String
    let autoStartup: Bool
    let providerGroups: [ProviderGroup]
    let proxyModeEnabled: Bool
    let proxyModePort: Int
    let proxyRequestTimeout: Int

    enum CodingKeys: String, CodingKey {
        case providers, currentProvider, autoUpdate, proxyHost, proxyPort, autoStartup, groups, providerGroups
        case proxyModeEnabled, proxyModePort, proxyRequestTimeout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.providers = try container.decode([APIProvider].self, forKey: .providers)
        self.currentProvider = try container.decodeIfPresent(APIProvider.self, forKey: .currentProvider)
        self.autoUpdate = try container.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? true
        self.proxyHost = try container.decodeIfPresent(String.self, forKey: .proxyHost) ?? ""
        self.proxyPort = try container.decodeIfPresent(String.self, forKey: .proxyPort) ?? ""
        self.autoStartup = try container.decodeIfPresent(Bool.self, forKey: .autoStartup) ?? false

        // 处理分组数据的兼容性：支持旧的 groups 字段和新的 providerGroups 字段
        // Handle groups data compatibility: support old 'groups' field and new 'providerGroups' field
        if let groups = try container.decodeIfPresent([ProviderGroup].self, forKey: .providerGroups) {
            self.providerGroups = groups
        } else if let oldGroups = try container.decodeIfPresent([String].self, forKey: .groups) {
            // 将旧格式转换为新格式
            // Convert old format to new format
            self.providerGroups = oldGroups.enumerated().map { ProviderGroup(name: $1, priority: $0) }
        } else {
            self.providerGroups = []
        }

        self.proxyModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .proxyModeEnabled) ?? false
        self.proxyModePort = try container.decodeIfPresent(Int.self, forKey: .proxyModePort) ?? AppConstants.ProxyPool.defaultPort
        self.proxyRequestTimeout = try container.decodeIfPresent(Int.self, forKey: .proxyRequestTimeout) ?? AppConstants.ProxyPool.defaultTimeout
    }

    init(providers: [APIProvider], currentProvider: APIProvider?, autoUpdate: Bool, proxyHost: String, proxyPort: String, autoStartup: Bool, providerGroups: [ProviderGroup] = [], proxyModeEnabled: Bool = false, proxyModePort: Int = AppConstants.ProxyPool.defaultPort, proxyRequestTimeout: Int = AppConstants.ProxyPool.defaultTimeout) {
        self.providers = providers
        self.currentProvider = currentProvider
        self.autoUpdate = autoUpdate
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.autoStartup = autoStartup
        self.providerGroups = providerGroups
        self.proxyModeEnabled = proxyModeEnabled
        self.proxyModePort = proxyModePort
        self.proxyRequestTimeout = proxyRequestTimeout
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providers, forKey: .providers)
        try container.encodeIfPresent(currentProvider, forKey: .currentProvider)
        try container.encode(autoUpdate, forKey: .autoUpdate)
        try container.encode(proxyHost, forKey: .proxyHost)
        try container.encode(proxyPort, forKey: .proxyPort)
        try container.encode(autoStartup, forKey: .autoStartup)
        try container.encode(providerGroups, forKey: .providerGroups)
        try container.encode(proxyModeEnabled, forKey: .proxyModeEnabled)
        try container.encode(proxyModePort, forKey: .proxyModePort)
        try container.encode(proxyRequestTimeout, forKey: .proxyRequestTimeout)
    }
}

// MARK: - Config Persistence Service 配置持久化服务

/// 配置文件持久化服务
/// Responsible for reading, writing, and migrating configuration files
class ConfigPersistence {

    // MARK: - Properties

    /// 应用配置文件路径
    /// App config file path
    private let appConfigPath: URL

    /// UserDefaults 实例（用于迁移和备份）
    /// UserDefaults instance (for migration and backup)
    private let userDefaults = UserDefaults.standard

    // MARK: - Initialization

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        appConfigPath = homeDir
            .appendingPathComponent(AppConstants.Paths.appConfigDir)
            .appendingPathComponent(AppConstants.Paths.appConfigFile)
    }

    // MARK: - Public Methods - Load & Save 加载和保存

    /// 加载配置
    /// Load configuration
    /// - Returns: 配置对象，如果加载失败返回 nil / Configuration object or nil if failed
    func loadConfig() -> AppConfig? {
        // 尝试从文件加载
        // Try to load from file
        if let config = try? loadConfigFromFile() {
            return config
        }

        // 如果文件不存在，尝试从 UserDefaults 迁移
        // If file doesn't exist, try to migrate from UserDefaults
        do {
            try migrateFromUserDefaults()
            // 迁移后重新加载
            // Reload after migration
            return try? loadConfigFromFile()
        } catch {
            print("配置加载和迁移失败: \(error)")
            return nil
        }
    }

    /// 保存配置
    /// Save configuration
    /// - Parameter config: 要保存的配置 / Configuration to save
    /// - Returns: 是否保存成功 / Whether save succeeded
    @discardableResult
    func saveConfig(_ config: AppConfig) -> Bool {
        do {
            try saveConfigToFile(config)
            print("配置保存到文件成功: \(appConfigPath.path)")

            // 验证保存的内容
            // Verify saved content
            if let savedData = try? Data(contentsOf: appConfigPath),
               let savedConfig = try? JSONDecoder().decode(AppConfig.self, from: savedData) {
                print("验证: 已保存 \(savedConfig.providers.count) 个提供商")
            }
            return true
        } catch {
            print("保存配置到文件失败: \(error)")
            // 如果文件保存失败，尝试保存到 UserDefaults 作为备用
            // If file save fails, try to save to UserDefaults as fallback
            saveToUserDefaultsFallback(config)
            return false
        }
    }

    // MARK: - Private Methods - File Operations 文件操作

    /// 从文件加载配置
    /// Load configuration from file
    private func loadConfigFromFile() throws -> AppConfig? {
        guard FileManager.default.fileExists(atPath: appConfigPath.path) else {
            return nil
        }

        let data = try Data(contentsOf: appConfigPath)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// 保存配置到文件
    /// Save configuration to file
    private func saveConfigToFile(_ config: AppConfig) throws {
        try ensureConfigDirectoryExists()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config)

        // 使用原子化写入
        // Use atomic write
        try atomicWrite(to: appConfigPath, data: data)

        // 设置文件权限为仅用户可读写
        // Set file permissions to user read/write only
        try FileManager.default.setAttributes(
            [.posixPermissions: AppConstants.Paths.configFilePermissions],
            ofItemAtPath: appConfigPath.path
        )
    }

    /// 原子化写入文件（防止写入过程中断导致文件损坏）
    /// Atomic file write (prevents file corruption if write is interrupted)
    private func atomicWrite(to url: URL, data: Data) throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString)

        // 写入临时文件
        // Write to temp file
        try data.write(to: tempFile)

        // 如果目标文件存在，先删除
        // If target file exists, delete it first
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // 原子性替换
        // Atomic replacement
        try FileManager.default.moveItem(at: tempFile, to: url)
    }

    /// 确保配置目录存在
    /// Ensure config directory exists
    private func ensureConfigDirectoryExists() throws {
        let configDir = appConfigPath.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: configDir.path) {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Private Methods - Migration 迁移

    /// 从 UserDefaults 迁移配置
    /// Migrate configuration from UserDefaults
    private func migrateFromUserDefaults() throws {
        // 检查是否有 UserDefaults 配置
        // Check if UserDefaults config exists
        guard userDefaults.data(forKey: "providers") != nil else {
            return // 没有需要迁移的配置 / No config to migrate
        }

        print("发现 UserDefaults 配置，开始迁移到 JSON 文件...")

        // 从 UserDefaults 读取配置
        // Read config from UserDefaults
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
        // Create config object
        let config = AppConfig(
            providers: providers,
            currentProvider: currentProvider,
            autoUpdate: autoUpdate,
            proxyHost: proxyHost,
            proxyPort: proxyPort,
            autoStartup: autoStartup
        )

        // 保存到文件
        // Save to file
        try saveConfigToFile(config)

        // 清理 UserDefaults
        // Clean up UserDefaults
        userDefaults.removeObject(forKey: "providers")
        userDefaults.removeObject(forKey: "currentProvider")
        userDefaults.removeObject(forKey: "autoUpdate")
        userDefaults.removeObject(forKey: "proxyHost")
        userDefaults.removeObject(forKey: "proxyPort")
        userDefaults.removeObject(forKey: "autoStartup")

        print("配置迁移完成")
    }

    /// 保存到 UserDefaults 作为备用
    /// Save to UserDefaults as fallback
    private func saveToUserDefaultsFallback(_ config: AppConfig) {
        // 备用方案：保存到 UserDefaults
        // Fallback: save to UserDefaults
        if let data = try? JSONEncoder().encode(config.providers) {
            userDefaults.set(data, forKey: "providers")
        }

        if let currentProvider = config.currentProvider,
           let data = try? JSONEncoder().encode(currentProvider) {
            userDefaults.set(data, forKey: "currentProvider")
        } else {
            userDefaults.removeObject(forKey: "currentProvider")
        }

        userDefaults.set(config.autoUpdate, forKey: "autoUpdate")
        userDefaults.set(config.proxyHost, forKey: "proxyHost")
        userDefaults.set(config.proxyPort, forKey: "proxyPort")

        print("配置已保存到 UserDefaults 备用")
    }
}
