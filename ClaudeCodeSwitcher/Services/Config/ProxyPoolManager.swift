import Foundation

/// 代理池管理服务
/// Proxy pool management service
class ProxyPoolManager {

    // MARK: - Public Methods - Provider Grouping 提供商分组

    /// 将提供商按分组组织
    /// Organize providers by groups
    /// - Parameters:
    ///   - providers: 提供商列表 / Provider list
    ///   - groups: 分组列表 / Group list
    /// - Returns: 分组后的结果 / Grouped result
    static func groupProviders(
        _ providers: [APIProvider],
        groups: [ProviderGroup]
    ) -> [(group: ProviderGroup?, providers: [APIProvider])] {
        var result: [(group: ProviderGroup?, providers: [APIProvider])] = []

        // 按优先级排序分组
        // Sort groups by priority
        let sortedGroups = groups.sorted { $0.priority < $1.priority }

        for group in sortedGroups {
            if group.isProxyGroup {
                // 代理池分组通过引用 ID 获取服务商
                // Proxy pool group gets providers through reference IDs
                let refProviders = group.providerRefs.compactMap { refId in
                    providers.first { $0.id == refId }
                }
                result.append((group: group, providers: refProviders))
            } else {
                // 普通分组通过 groupName 匹配
                // Normal group matches by groupName
                let groupProviders = providers
                    .filter { $0.groupName == group.name }
                    .sorted { $0.priority < $1.priority }
                result.append((group: group, providers: groupProviders))
            }
        }

        // 添加未分组的提供商
        // Add ungrouped providers
        let ungrouped = providers
            .filter { $0.groupName == nil || $0.groupName?.isEmpty == true }
            .sorted { $0.priority < $1.priority }

        if !ungrouped.isEmpty || sortedGroups.isEmpty {
            result.append((group: nil, providers: ungrouped))
        }

        return result
    }

    /// 获取代理池中的提供商
    /// Get providers in proxy pool
    /// - Parameters:
    ///   - providers: 所有提供商 / All providers
    ///   - groups: 分组列表 / Group list
    /// - Returns: 代理池中的有效提供商 / Valid providers in proxy pool
    static func getProxyPoolProviders(
        from providers: [APIProvider],
        groups: [ProviderGroup]
    ) -> [APIProvider] {
        guard let proxyGroup = groups.first(where: { $0.isProxyGroup }) else {
            return []
        }

        return proxyGroup.providerRefs.compactMap { refId in
            providers.first { $0.id == refId && $0.isValid }
        }
    }

    /// 检查提供商是否在代理池中
    /// Check if provider is in proxy pool
    /// - Parameters:
    ///   - provider: 提供商 / Provider
    ///   - groups: 分组列表 / Group list
    /// - Returns: 是否在代理池中 / Whether in proxy pool
    static func isInProxyPool(
        provider: APIProvider,
        groups: [ProviderGroup]
    ) -> Bool {
        guard let proxyGroup = groups.first(where: { $0.isProxyGroup }) else {
            return false
        }
        return proxyGroup.providerRefs.contains(provider.id)
    }

    // MARK: - Public Methods - Group Management 分组管理

    /// 确保代理池分组存在
    /// Ensure proxy pool group exists
    /// - Parameter groups: 当前分组列表 / Current group list
    /// - Returns: 更新后的分组列表 / Updated group list
    static func ensureProxyGroupExists(in groups: [ProviderGroup]) -> [ProviderGroup] {
        var updatedGroups = groups

        // 如果代理池分组不存在，创建它
        // Create proxy pool group if it doesn't exist
        if !updatedGroups.contains(where: { $0.isProxyGroup }) {
            updatedGroups.insert(ProviderGroup.createProxyGroup(), at: 0)
        }

        return updatedGroups
    }

    /// 添加提供商到代理池
    /// Add provider to proxy pool
    /// - Parameters:
    ///   - provider: 要添加的提供商 / Provider to add
    ///   - groups: 当前分组列表 / Current group list
    /// - Returns: 更新后的分组列表（如果有变化）/ Updated group list (if changed)
    static func addToProxyPool(
        provider: APIProvider,
        groups: [ProviderGroup]
    ) -> [ProviderGroup]? {
        guard let index = groups.firstIndex(where: { $0.isProxyGroup }) else {
            return nil
        }

        var updatedGroups = groups

        // 如果已经在代理池中，不做任何操作
        // If already in proxy pool, do nothing
        guard !updatedGroups[index].providerRefs.contains(provider.id) else {
            return nil
        }

        // 添加引用
        // Add reference
        updatedGroups[index].providerRefs.append(provider.id)
        return updatedGroups
    }

    /// 从代理池移除提供商
    /// Remove provider from proxy pool
    /// - Parameters:
    ///   - provider: 要移除的提供商 / Provider to remove
    ///   - groups: 当前分组列表 / Current group list
    /// - Returns: 更新后的分组列表（如果有变化）/ Updated group list (if changed)
    static func removeFromProxyPool(
        provider: APIProvider,
        groups: [ProviderGroup]
    ) -> [ProviderGroup]? {
        guard let index = groups.firstIndex(where: { $0.isProxyGroup }) else {
            return nil
        }

        var updatedGroups = groups

        // 移除引用
        // Remove reference
        let originalCount = updatedGroups[index].providerRefs.count
        updatedGroups[index].providerRefs.removeAll { $0 == provider.id }

        // 如果没有变化，返回 nil
        // Return nil if no change
        if updatedGroups[index].providerRefs.count == originalCount {
            return nil
        }

        return updatedGroups
    }

    /// 当提供商被删除时，从代理池中移除其引用
    /// Remove provider reference from proxy pool when provider is deleted
    /// - Parameters:
    ///   - providerId: 被删除的提供商 ID / Deleted provider ID
    ///   - groups: 当前分组列表 / Current group list
    /// - Returns: 更新后的分组列表（如果有变化）/ Updated group list (if changed)
    static func removeProviderReferences(
        providerId: UUID,
        from groups: [ProviderGroup]
    ) -> [ProviderGroup]? {
        guard let index = groups.firstIndex(where: { $0.isProxyGroup }) else {
            return nil
        }

        var updatedGroups = groups

        let originalCount = updatedGroups[index].providerRefs.count
        updatedGroups[index].providerRefs.removeAll { $0 == providerId }

        // 如果没有变化，返回 nil
        // Return nil if no change
        if updatedGroups[index].providerRefs.count == originalCount {
            return nil
        }

        return updatedGroups
    }

    // MARK: - Public Methods - Group Operations 分组操作

    /// 更新分组时，同步更新提供商的 groupName
    /// When updating group, sync provider groupName
    /// - Parameters:
    ///   - oldName: 旧分组名 / Old group name
    ///   - newName: 新分组名 / New group name
    ///   - providers: 提供商列表 / Provider list
    /// - Returns: 更新后的提供商列表 / Updated provider list
    static func updateProviderGroupNames(
        from oldName: String,
        to newName: String,
        providers: [APIProvider]
    ) -> [APIProvider] {
        return providers.map { provider in
            if provider.groupName == oldName {
                var updated = provider
                updated.groupName = newName
                return updated
            }
            return provider
        }
    }

    /// 删除分组时，将该分组的提供商移到未分组
    /// When deleting group, move its providers to ungrouped
    /// - Parameters:
    ///   - groupName: 要删除的分组名 / Group name to delete
    ///   - providers: 提供商列表 / Provider list
    /// - Returns: 更新后的提供商列表 / Updated provider list
    static func clearGroupForProviders(
        groupName: String,
        providers: [APIProvider]
    ) -> [APIProvider] {
        return providers.map { provider in
            if provider.groupName == groupName {
                var updated = provider
                updated.groupName = nil
                return updated
            }
            return provider
        }
    }
}
