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
        if let groups = try container.decodeIfPresent([ProviderGroup].self, forKey: .providerGroups) {
            self.providerGroups = groups
        } else if let oldGroups = try container.decodeIfPresent([String].self, forKey: .groups) {
            self.providerGroups = oldGroups.enumerated().map { ProviderGroup(name: $1, priority: $0) }
        } else {
            self.providerGroups = []
        }
        self.proxyModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .proxyModeEnabled) ?? false
        self.proxyModePort = try container.decodeIfPresent(Int.self, forKey: .proxyModePort) ?? 32000
        self.proxyRequestTimeout = try container.decodeIfPresent(Int.self, forKey: .proxyRequestTimeout) ?? 120
    }

    init(providers: [APIProvider], currentProvider: APIProvider?, autoUpdate: Bool, proxyHost: String, proxyPort: String, autoStartup: Bool, providerGroups: [ProviderGroup] = [], proxyModeEnabled: Bool = false, proxyModePort: Int = 32000, proxyRequestTimeout: Int = 120) {
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

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published var providers: [APIProvider] = []
    @Published var currentProvider: APIProvider?
    @Published var autoUpdate: Bool = true
    @Published var proxyHost: String = ""
    @Published var proxyPort: String = ""
    @Published var autoStartup: Bool = false
    @Published var providerGroups: [ProviderGroup] = []
    @Published var proxyModeEnabled: Bool = false
    @Published var proxyModePort: Int = 32000
    @Published var proxyRequestTimeout: Int = 120

    var groups: [String] {
        providerGroups.sorted { $0.priority < $1.priority }.map { $0.name }
    }

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

    func reloadConfiguration() {
        print("=== reloadConfiguration() 被调用 ===")
        DispatchQueue.main.async {
            print("=== 开始在主线程重新加载配置 ===")
            self.loadConfiguration()
        }
    }

    func getProviders() -> [APIProvider] {
        return providers
    }

    func addProvider(_ provider: APIProvider) {
        objectWillChange.send()
        print("添加新提供商: \(provider.name)")
        // 重新赋值以确保 @Published 触发变更
        providers = providers + [provider]
        print("当前提供商列表: \(providers.map { $0.name })")
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }

    func updateProvider(_ provider: APIProvider) {
        objectWillChange.send()
        if providers.contains(where: { $0.id == provider.id }) {
            // 重新赋值以确保 @Published 触发变更
            providers = providers.map { $0.id == provider.id ? provider : $0 }

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
        objectWillChange.send()
        // 重新赋值以确保 @Published 触发变更
        providers = providers.filter { $0.id != provider.id }

        // 如果删除的是当前提供商，清空当前提供商
        if currentProvider?.id == provider.id {
            currentProvider = nil
        }

        // 从代理池引用中移除该服务商
        if let index = providerGroups.firstIndex(where: { $0.isProxyGroup }) {
            providerGroups[index].providerRefs.removeAll { $0 == provider.id }
        }

        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }

    func setCurrentProvider(_ provider: APIProvider) {
        objectWillChange.send()
        currentProvider = provider
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }

    func copyProvider(_ provider: APIProvider) {
        objectWillChange.send()
        let copiedProvider = APIProvider(
            name: provider.name + "-复制",
            url: provider.url,
            key: provider.key,
            largeModel: provider.largeModel,
            smallModel: provider.smallModel,
            groupName: provider.groupName
        )
        providers = providers + [copiedProvider]
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }

    // MARK: - Group Management

    func addGroup(_ name: String) {
        guard !name.isEmpty,
              name != ProviderGroup.proxyGroupName,
              !providerGroups.contains(where: { $0.name == name }) else { return }
        objectWillChange.send()
        let maxPriority = providerGroups.filter { !$0.isBuiltin }.map { $0.priority }.max() ?? -1
        providerGroups = providerGroups + [ProviderGroup(name: name, priority: maxPriority + 1)]
        saveConfiguration()
    }

    func removeGroup(_ name: String) {
        guard let group = providerGroups.first(where: { $0.name == name }), !group.isBuiltin else { return }
        objectWillChange.send()
        providerGroups = providerGroups.filter { $0.name != name }
        providers = providers.map { provider in
            if provider.groupName == name {
                var updated = provider
                updated.groupName = nil
                return updated
            }
            return provider
        }
        saveConfiguration()
        postConfigChangeNotification()
    }

    func updateGroup(_ group: ProviderGroup) {
        guard let existing = providerGroups.first(where: { $0.id == group.id }) else { return }
        if existing.isBuiltin && group.name != existing.name { return }
        objectWillChange.send()
        let oldName = existing.name
        providerGroups = providerGroups.map { $0.id == group.id ? group : $0 }
        if oldName != group.name {
            providers = providers.map { provider in
                if provider.groupName == oldName {
                    var updated = provider
                    updated.groupName = group.name
                    return updated
                }
                return provider
            }
        }
        saveConfiguration()
        postConfigChangeNotification()
    }

    func getGroup(byName name: String) -> ProviderGroup? {
        providerGroups.first { $0.name == name }
    }

    func providersGrouped() -> [(group: ProviderGroup?, providers: [APIProvider])] {
        var result: [(group: ProviderGroup?, providers: [APIProvider])] = []

        let sortedGroups = providerGroups.sorted { $0.priority < $1.priority }
        for group in sortedGroups {
            if group.isProxyGroup {
                // 代理池分组通过引用 ID 获取服务商
                let refProviders = group.providerRefs.compactMap { refId in
                    providers.first { $0.id == refId }
                }
                result.append((group: group, providers: refProviders))
            } else {
                let groupProviders = providers.filter { $0.groupName == group.name }.sorted { $0.priority < $1.priority }
                result.append((group: group, providers: groupProviders))
            }
        }

        let ungrouped = providers.filter { $0.groupName == nil || $0.groupName?.isEmpty == true }.sorted { $0.priority < $1.priority }
        if !ungrouped.isEmpty || sortedGroups.isEmpty {
            result.append((group: nil, providers: ungrouped))
        }

        return result
    }

    func getProxyPoolProviders() -> [APIProvider] {
        guard let proxyGroup = providerGroups.first(where: { $0.isProxyGroup }) else {
            return []
        }
        return proxyGroup.providerRefs.compactMap { refId in
            providers.first { $0.id == refId && $0.isValid }
        }
    }

    // MARK: - Proxy Pool Reference Management

    func addToProxyPool(_ provider: APIProvider) {
        guard let index = providerGroups.firstIndex(where: { $0.isProxyGroup }) else { return }
        guard !providerGroups[index].providerRefs.contains(provider.id) else { return }
        objectWillChange.send()
        providerGroups[index].providerRefs.append(provider.id)
        saveConfiguration()
        postConfigChangeNotification()
    }

    func removeFromProxyPool(_ provider: APIProvider) {
        guard let index = providerGroups.firstIndex(where: { $0.isProxyGroup }) else { return }
        objectWillChange.send()
        providerGroups[index].providerRefs.removeAll { $0 == provider.id }
        saveConfiguration()
        postConfigChangeNotification()
    }

    func isInProxyPool(_ provider: APIProvider) -> Bool {
        guard let proxyGroup = providerGroups.first(where: { $0.isProxyGroup }) else { return false }
        return proxyGroup.providerRefs.contains(provider.id)
    }

    // MARK: - Proxy Mode

    func setProxyModeEnabled(_ enabled: Bool) {
        objectWillChange.send()
        proxyModeEnabled = enabled
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
        NotificationCenter.default.post(name: .proxyModeDidChange, object: nil, userInfo: ["enabled": enabled])
    }

    func setProxyModePort(_ port: Int) {
        objectWillChange.send()
        proxyModePort = port
        saveConfiguration()
        if proxyModeEnabled {
            syncToClaudeConfig()
        }
        postConfigChangeNotification()
    }

    func setProxyRequestTimeout(_ timeout: Int) {
        objectWillChange.send()
        proxyRequestTimeout = max(10, min(600, timeout)) // 限制在 10-600 秒之间
        saveConfiguration()
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
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
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
        if let config = try? loadConfigFromFile() {
            self.providers = config.providers
            self.currentProvider = config.currentProvider
            self.autoUpdate = config.autoUpdate
            self.proxyHost = config.proxyHost
            self.proxyPort = config.proxyPort
            self.autoStartup = config.autoStartup
            self.providerGroups = config.providerGroups
            self.proxyModeEnabled = config.proxyModeEnabled
            self.proxyModePort = config.proxyModePort
            self.proxyRequestTimeout = config.proxyRequestTimeout
            ensureProxyGroupExists()
            DispatchQueue.main.async {
                self.postConfigChangeNotification()
            }
            return
        }

        do {
            try migrateFromUserDefaults()
            if let config = try? loadConfigFromFile() {
                self.providers = config.providers
                self.currentProvider = config.currentProvider
                self.autoUpdate = config.autoUpdate
                self.proxyHost = config.proxyHost
                self.proxyPort = config.proxyPort
                self.autoStartup = config.autoStartup
                self.providerGroups = config.providerGroups
                self.proxyModeEnabled = config.proxyModeEnabled
                self.proxyModePort = config.proxyModePort
                self.proxyRequestTimeout = config.proxyRequestTimeout
                ensureProxyGroupExists()
                DispatchQueue.main.async {
                    self.postConfigChangeNotification()
                }
            }
        } catch {
            self.providers = []
            self.currentProvider = nil
            self.autoUpdate = true
            self.proxyHost = ""
            self.proxyPort = ""
            self.autoStartup = false
            self.providerGroups = []
            self.proxyModeEnabled = false
            self.proxyModePort = 32000
            self.proxyRequestTimeout = 120
            ensureProxyGroupExists()
        }
    }

    private func ensureProxyGroupExists() {
        if !providerGroups.contains(where: { $0.isProxyGroup }) {
            providerGroups.insert(ProviderGroup.createProxyGroup(), at: 0)
            saveConfiguration()
        }
    }

    private func saveConfiguration() {
        let config = AppConfig(
            providers: providers,
            currentProvider: currentProvider,
            autoUpdate: autoUpdate,
            proxyHost: proxyHost,
            proxyPort: proxyPort,
            autoStartup: autoStartup,
            providerGroups: providerGroups,
            proxyModeEnabled: proxyModeEnabled,
            proxyModePort: proxyModePort,
            proxyRequestTimeout: proxyRequestTimeout
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

            // 读取现有配置并保留未受管理的字段
            var claudeConfig = loadClaudeConfigDictionary()

            // 更新 Switcher 管理的字段
            updateSwitcherManagedFields(&claudeConfig)

            // 写入配置文件
            try writeClaudeConfigDictionary(claudeConfig)

            print("已同步配置到 Claude 配置文件: \(claudeConfigPath.path)")

        } catch {
            print("同步 Claude 配置失败: \(error)")
        }
    }

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

    private func writeClaudeConfigDictionary(_ config: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: claudeConfigPath, options: .atomic)

        // 设置文件权限为仅用户可读写
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claudeConfigPath.path)
    }

    static let proxyModeDefaultKey = "ccs-proxy-mode"

    private func updateSwitcherManagedFields(_ config: inout [String: Any]) {
        var env = config["env"] as? [String: Any] ?? [:]

        if proxyModeEnabled {
            env["ANTHROPIC_API_KEY"] = Self.proxyModeDefaultKey
            env["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:\(proxyModePort)"
            env.removeValue(forKey: "ANTHROPIC_MODEL")
            env.removeValue(forKey: "ANTHROPIC_SMALL_FAST_MODEL")
        } else if let provider = currentProvider {
            env["ANTHROPIC_API_KEY"] = provider.key
            env["ANTHROPIC_BASE_URL"] = provider.url

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
            env["ANTHROPIC_API_KEY"] = ""
            env["ANTHROPIC_BASE_URL"] = ""
            env.removeValue(forKey: "ANTHROPIC_MODEL")
            env.removeValue(forKey: "ANTHROPIC_SMALL_FAST_MODEL")
        }

        let proxyUrl = buildProxyUrl()
        if !proxyUrl.isEmpty {
            env["HTTPS_PROXY"] = proxyUrl
            env["HTTP_PROXY"] = proxyUrl
        } else {
            env.removeValue(forKey: "HTTPS_PROXY")
            env.removeValue(forKey: "HTTP_PROXY")
        }

        if !env.isEmpty {
            config["env"] = env
        } else {
            config.removeValue(forKey: "env")
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
    static let balanceDidUpdate = Notification.Name("balanceDidUpdate")
    static let proxyModeDidChange = Notification.Name("proxyModeDidChange")
}
