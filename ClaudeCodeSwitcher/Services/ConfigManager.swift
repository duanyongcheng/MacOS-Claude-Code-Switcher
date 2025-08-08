import Foundation
import Combine
import AppKit

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
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if #available(macOS 10.15, *) {
                encoder.outputFormatting.insert(.withoutEscapingSlashes)
            }
            let data = try encoder.encode(config)
            try data.write(to: claudeConfigPath)
            
            print("已同步配置到 Claude 配置文件: \(claudeConfigPath.path)")
            
        } catch {
            print("同步 Claude 配置失败: \(error)")
        }
    }
    
    private func buildClaudeConfig(existing: ClaudeConfig?) -> ClaudeConfig {
        let proxyUrl = buildProxyUrl()
        
        let env = ClaudeConfig.ClaudeEnvironment(
            ANTHROPIC_API_KEY: currentProvider?.key ?? "",
            ANTHROPIC_BASE_URL: currentProvider?.url ?? "",
            ANTHROPIC_MODEL: currentProvider?.largeModel,
            ANTHROPIC_SMALL_FAST_MODEL: currentProvider?.smallModel,
            CLAUDE_CODE_MAX_OUTPUT_TOKENS: existing?.env.CLAUDE_CODE_MAX_OUTPUT_TOKENS,
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: existing?.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC,
            HTTPS_PROXY: proxyUrl.isEmpty ? nil : proxyUrl,
            HTTP_PROXY: proxyUrl.isEmpty ? nil : proxyUrl
        )
        
        return ClaudeConfig(
            env: env,
            feedbackSurveyState: existing?.feedbackSurveyState
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