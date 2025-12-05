import Foundation
import Combine
import AppKit

/// 配置管理器
/// Main configuration manager coordinating various config services
class ConfigManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ConfigManager()

    // MARK: - Published Properties 发布属性

    @Published var providers: [APIProvider] = []
    @Published var currentProvider: APIProvider?
    @Published var autoUpdate: Bool = true
    @Published var proxyHost: String = ""
    @Published var proxyPort: String = ""
    @Published var autoStartup: Bool = false
    @Published var providerGroups: [ProviderGroup] = []
    @Published var proxyModeEnabled: Bool = false
    @Published var proxyModePort: Int = AppConstants.ProxyPool.defaultPort
    @Published var proxyRequestTimeout: Int = AppConstants.ProxyPool.defaultTimeout

    // MARK: - Computed Properties 计算属性

    /// 获取排序后的分组名称列表
    /// Get sorted group name list
    var groups: [String] {
        providerGroups.sorted { $0.priority < $1.priority }.map { $0.name }
    }

    // MARK: - Services 服务

    private let persistence: ConfigPersistence
    private let claudeSync: ClaudeSyncService
    private let launchAgent: LaunchAgentService

    // MARK: - Initialization 初始化

    private init() {
        self.persistence = ConfigPersistence()
        self.claudeSync = ClaudeSyncService()
        self.launchAgent = LaunchAgentService.shared

        loadConfiguration()
    }

    // MARK: - Public Methods - Configuration Loading 配置加载

    /// 重新加载配置
    /// Reload configuration
    func reloadConfiguration() {
        print("=== reloadConfiguration() 被调用 ===")
        DispatchQueue.main.async {
            print("=== 开始在主线程重新加载配置 ===")
            self.loadConfiguration()
        }
    }

    // MARK: - Public Methods - Provider Management 提供商管理

    /// 获取所有提供商
    /// Get all providers
    func getProviders() -> [APIProvider] {
        return providers
    }

    /// 添加提供商
    /// Add provider
    func addProvider(_ provider: APIProvider) {
        objectWillChange.send()
        print("添加新提供商: \(provider.name)")
        providers = providers + [provider]
        print("当前提供商列表: \(providers.map { $0.name })")
        saveAndSync()
    }

    /// 更新提供商
    /// Update provider
    func updateProvider(_ provider: APIProvider) {
        objectWillChange.send()
        if providers.contains(where: { $0.id == provider.id }) {
            providers = providers.map { $0.id == provider.id ? provider : $0 }

            // 如果更新的是当前提供商，也要更新当前提供商
            // If updating current provider, also update current provider
            if currentProvider?.id == provider.id {
                currentProvider = provider
            }

            saveAndSync()
        }
    }

    /// 删除提供商
    /// Remove provider
    func removeProvider(_ provider: APIProvider) {
        objectWillChange.send()
        providers = providers.filter { $0.id != provider.id }

        // 如果删除的是当前提供商，清空当前提供商
        // If deleting current provider, clear it
        if currentProvider?.id == provider.id {
            currentProvider = nil
        }

        // 从代理池引用中移除该服务商
        // Remove from proxy pool references
        if let updatedGroups = ProxyPoolManager.removeProviderReferences(providerId: provider.id, from: providerGroups) {
            providerGroups = updatedGroups
        }

        saveAndSync()
    }

    /// 设置当前提供商
    /// Set current provider
    func setCurrentProvider(_ provider: APIProvider) {
        objectWillChange.send()
        currentProvider = provider
        saveAndSync()
    }

    /// 复制提供商
    /// Copy provider
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
        saveAndSync()
    }

    // MARK: - Public Methods - Group Management 分组管理

    /// 添加分组
    /// Add group
    func addGroup(_ name: String) {
        guard !name.isEmpty,
              name != AppConstants.ProxyPool.name,
              !providerGroups.contains(where: { $0.name == name }) else { return }

        objectWillChange.send()
        let maxPriority = providerGroups.filter { !$0.isBuiltin }.map { $0.priority }.max() ?? -1
        providerGroups = providerGroups + [ProviderGroup(name: name, priority: maxPriority + 1)]
        saveConfiguration()
    }

    /// 删除分组
    /// Remove group
    func removeGroup(_ name: String) {
        guard let group = providerGroups.first(where: { $0.name == name }), !group.isBuiltin else { return }

        objectWillChange.send()
        providerGroups = providerGroups.filter { $0.name != name }

        // 将该分组的提供商移到未分组
        // Move group's providers to ungrouped
        providers = ProxyPoolManager.clearGroupForProviders(groupName: name, providers: providers)

        saveConfiguration()
        postConfigChangeNotification()
    }

    /// 更新分组
    /// Update group
    func updateGroup(_ group: ProviderGroup) {
        guard let existing = providerGroups.first(where: { $0.id == group.id }) else { return }
        if existing.isBuiltin && group.name != existing.name { return }

        objectWillChange.send()
        let oldName = existing.name
        providerGroups = providerGroups.map { $0.id == group.id ? group : $0 }

        // 如果名称改变了，同步更新提供商的 groupName
        // If name changed, sync update provider groupName
        if oldName != group.name {
            providers = ProxyPoolManager.updateProviderGroupNames(from: oldName, to: group.name, providers: providers)
        }

        saveConfiguration()
        postConfigChangeNotification()
    }

    /// 获取分组
    /// Get group by name
    func getGroup(byName name: String) -> ProviderGroup? {
        providerGroups.first { $0.name == name }
    }

    /// 获取分组后的提供商
    /// Get grouped providers
    func providersGrouped() -> [(group: ProviderGroup?, providers: [APIProvider])] {
        return ProxyPoolManager.groupProviders(providers, groups: providerGroups)
    }

    // MARK: - Public Methods - Proxy Pool 代理池

    /// 获取代理池中的提供商
    /// Get proxy pool providers
    func getProxyPoolProviders() -> [APIProvider] {
        return ProxyPoolManager.getProxyPoolProviders(from: providers, groups: providerGroups)
    }

    /// 添加到代理池
    /// Add to proxy pool
    func addToProxyPool(_ provider: APIProvider) {
        guard let updatedGroups = ProxyPoolManager.addToProxyPool(provider: provider, groups: providerGroups) else {
            return
        }

        objectWillChange.send()
        providerGroups = updatedGroups
        saveConfiguration()
        postConfigChangeNotification()
    }

    /// 从代理池移除
    /// Remove from proxy pool
    func removeFromProxyPool(_ provider: APIProvider) {
        guard let updatedGroups = ProxyPoolManager.removeFromProxyPool(provider: provider, groups: providerGroups) else {
            return
        }

        objectWillChange.send()
        providerGroups = updatedGroups
        saveConfiguration()
        postConfigChangeNotification()
    }

    /// 检查是否在代理池中
    /// Check if in proxy pool
    func isInProxyPool(_ provider: APIProvider) -> Bool {
        return ProxyPoolManager.isInProxyPool(provider: provider, groups: providerGroups)
    }

    // MARK: - Public Methods - Proxy Mode 代理模式

    /// 设置代理模式启用状态
    /// Set proxy mode enabled
    func setProxyModeEnabled(_ enabled: Bool) {
        objectWillChange.send()
        proxyModeEnabled = enabled
        saveAndSync()
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.proxyModeDidChange),
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }

    /// 设置代理模式端口
    /// Set proxy mode port
    func setProxyModePort(_ port: Int) {
        objectWillChange.send()
        proxyModePort = port
        saveConfiguration()
        if proxyModeEnabled {
            syncToClaudeConfig()
        }
        postConfigChangeNotification()
    }

    /// 设置代理请求超时
    /// Set proxy request timeout
    func setProxyRequestTimeout(_ timeout: Int) {
        objectWillChange.send()
        // 限制在允许范围内
        // Limit to allowed range
        proxyRequestTimeout = max(
            AppConstants.ProxyPool.minTimeout,
            min(AppConstants.ProxyPool.maxTimeout, timeout)
        )
        saveConfiguration()
        postConfigChangeNotification()
    }

    // MARK: - Public Methods - Global Settings 全局设置

    /// 更新全局设置
    /// Update global settings
    func updateGlobalSettings(autoUpdate: Bool, proxyHost: String, proxyPort: String, autoStartup: Bool) {
        self.autoUpdate = autoUpdate
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort

        // 更新开机自启动设置
        // Update auto-startup setting
        let wasAutoStartup = self.autoStartup
        self.autoStartup = autoStartup

        if wasAutoStartup != autoStartup {
            launchAgent.updateStatus(autoStartup)
        } else if autoStartup {
            // 如果开机自启已启用但状态不正确，重新安装
            // If auto-startup is enabled but status is incorrect, reinstall
            if !launchAgent.checkStatus() {
                print("检测到 Launch Agent 状态不正确，重新安装...")
                launchAgent.updateStatus(true)
            }
        }

        saveAndSync()
    }

    /// 检查 Launch Agent 状态
    /// Check Launch Agent status
    func checkLaunchAgentStatus() -> Bool {
        return launchAgent.checkStatus()
    }

    // MARK: - Private Methods - Save & Sync 保存和同步

    /// 保存配置并同步到 Claude
    /// Save configuration and sync to Claude
    private func saveAndSync() {
        saveConfiguration()
        syncToClaudeConfig()
        postConfigChangeNotification()
    }

    /// 保存配置
    /// Save configuration
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

        persistence.saveConfig(config)
    }

    /// 同步到 Claude 配置
    /// Sync to Claude config
    private func syncToClaudeConfig() {
        claudeSync.syncToClaudeConfig(
            provider: currentProvider,
            proxyHost: proxyHost,
            proxyPort: proxyPort,
            proxyModeEnabled: proxyModeEnabled,
            proxyModePort: proxyModePort
        )
    }

    /// 发送配置变更通知
    /// Post configuration change notification
    private func postConfigChangeNotification() {
        NotificationCenter.default.post(name: NSNotification.Name(AppConstants.Notifications.configDidChange), object: nil)
    }

    // MARK: - Private Methods - Load 加载

    /// 加载配置
    /// Load configuration
    private func loadConfiguration() {
        if let config = persistence.loadConfig() {
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
        } else {
            // 加载失败，使用默认值
            // Load failed, use default values
            self.providers = []
            self.currentProvider = nil
            self.autoUpdate = true
            self.proxyHost = ""
            self.proxyPort = ""
            self.autoStartup = false
            self.providerGroups = []
            self.proxyModeEnabled = false
            self.proxyModePort = AppConstants.ProxyPool.defaultPort
            self.proxyRequestTimeout = AppConstants.ProxyPool.defaultTimeout
            ensureProxyGroupExists()
        }
    }

    /// 确保代理池分组存在
    /// Ensure proxy pool group exists
    private func ensureProxyGroupExists() {
        providerGroups = ProxyPoolManager.ensureProxyGroupExists(in: providerGroups)
        if !providerGroups.contains(where: { $0.isProxyGroup }) {
            saveConfiguration()
        }
    }
}

// MARK: - Notification Names 通知名称

extension Notification.Name {
    static let configDidChange = Notification.Name(AppConstants.Notifications.configDidChange)
    static let balanceDidUpdate = Notification.Name(AppConstants.Notifications.balanceDidUpdate)
    static let proxyModeDidChange = Notification.Name(AppConstants.Notifications.proxyModeDidChange)
}
