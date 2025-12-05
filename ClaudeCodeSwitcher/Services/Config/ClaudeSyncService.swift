import Foundation

/// Claude 配置同步服务
/// Syncs provider configuration to Claude Code's settings.json
class ClaudeSyncService {

    // MARK: - Properties

    /// Claude 配置文件路径
    /// Claude config file path
    private let claudeConfigPath: URL

    // MARK: - Initialization

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        claudeConfigPath = homeDir
            .appendingPathComponent(AppConstants.Paths.claudeDir)
            .appendingPathComponent(AppConstants.Paths.claudeConfigFile)
    }

    // MARK: - Public Methods

    /// 同步配置到 Claude settings.json
    /// Sync configuration to Claude settings.json
    /// - Parameters:
    ///   - provider: 当前提供商 / Current provider
    ///   - proxyHost: 代理主机 / Proxy host
    ///   - proxyPort: 代理端口 / Proxy port
    ///   - proxyModeEnabled: 是否启用代理池模式 / Whether proxy mode is enabled
    ///   - proxyModePort: 代理池端口 / Proxy pool port
    func syncToClaudeConfig(
        provider: APIProvider?,
        proxyHost: String,
        proxyPort: String,
        proxyModeEnabled: Bool,
        proxyModePort: Int
    ) {
        do {
            // 确保 .claude 目录存在
            // Ensure .claude directory exists
            let claudeDir = claudeConfigPath.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: claudeDir.path) {
                try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            }

            // 读取现有配置并保留未受管理的字段
            // Read existing config and preserve unmanaged fields
            var claudeConfig = loadClaudeConfigDictionary()

            // 更新 Switcher 管理的字段
            // Update Switcher-managed fields
            updateSwitcherManagedFields(
                &claudeConfig,
                provider: provider,
                proxyHost: proxyHost,
                proxyPort: proxyPort,
                proxyModeEnabled: proxyModeEnabled,
                proxyModePort: proxyModePort
            )

            // 写入配置文件
            // Write config file
            try writeClaudeConfigDictionary(claudeConfig)

            print("已同步配置到 Claude 配置文件: \(claudeConfigPath.path)")

        } catch {
            print("同步 Claude 配置失败: \(error)")
        }
    }

    // MARK: - Private Methods - Read & Write 读写操作

    /// 加载 Claude 配置字典
    /// Load Claude config as dictionary
    private func loadClaudeConfigDictionary() -> [String: Any] {
        guard FileManager.default.fileExists(atPath: claudeConfigPath.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: claudeConfigPath)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            if let dictionary = jsonObject as? [String: Any] {
                return dictionary
            } else {
                print("现有 Claude 配置不是对象，将使用空配置")
            }
        } catch {
            print("读取 Claude 配置失败: \(error)，将使用空配置")
        }

        return [:]
    }

    /// 写入 Claude 配置字典
    /// Write Claude config dictionary
    private func writeClaudeConfigDictionary(_ config: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: claudeConfigPath, options: .atomic)

        // 设置文件权限为仅用户可读写
        // Set file permissions to user read/write only
        try FileManager.default.setAttributes(
            [.posixPermissions: AppConstants.Paths.configFilePermissions],
            ofItemAtPath: claudeConfigPath.path
        )
    }

    // MARK: - Private Methods - Config Update 配置更新

    /// 更新 Switcher 管理的字段
    /// Update Switcher-managed fields
    private func updateSwitcherManagedFields(
        _ config: inout [String: Any],
        provider: APIProvider?,
        proxyHost: String,
        proxyPort: String,
        proxyModeEnabled: Bool,
        proxyModePort: Int
    ) {
        var env = config["env"] as? [String: Any] ?? [:]

        if proxyModeEnabled {
            // 代理池模式：使用本地代理
            // Proxy pool mode: use local proxy
            env["ANTHROPIC_API_KEY"] = AppConstants.API.proxyModeKey
            env["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:\(proxyModePort)"
            env.removeValue(forKey: "ANTHROPIC_MODEL")
            env.removeValue(forKey: "ANTHROPIC_SMALL_FAST_MODEL")
        } else if let provider = provider {
            // 普通模式：使用选定的提供商
            // Normal mode: use selected provider
            env["ANTHROPIC_API_KEY"] = provider.key
            env["ANTHROPIC_BASE_URL"] = provider.url

            // 设置模型配置
            // Set model configuration
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
            // 未选择提供商：清空配置
            // No provider selected: clear config
            env["ANTHROPIC_API_KEY"] = ""
            env["ANTHROPIC_BASE_URL"] = ""
            env.removeValue(forKey: "ANTHROPIC_MODEL")
            env.removeValue(forKey: "ANTHROPIC_SMALL_FAST_MODEL")
        }

        // 设置代理配置
        // Set proxy configuration
        let proxyUrl = buildProxyUrl(proxyHost: proxyHost, proxyPort: proxyPort)
        if !proxyUrl.isEmpty {
            env["HTTPS_PROXY"] = proxyUrl
            env["HTTP_PROXY"] = proxyUrl
        } else {
            env.removeValue(forKey: "HTTPS_PROXY")
            env.removeValue(forKey: "HTTP_PROXY")
        }

        // 更新配置字典
        // Update config dictionary
        if !env.isEmpty {
            config["env"] = env
        } else {
            config.removeValue(forKey: "env")
        }
    }

    /// 构建代理 URL
    /// Build proxy URL
    private func buildProxyUrl(proxyHost: String, proxyPort: String) -> String {
        guard !proxyHost.isEmpty else { return "" }

        let host = proxyHost
        let port = proxyPort.isEmpty ? "" : ":\(proxyPort)"
        let url = "\(host)\(port)"

        // 如果已经包含协议，直接返回
        // If already contains protocol, return directly
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return url
        } else {
            return "http://\(url)"
        }
    }
}
