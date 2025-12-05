import Foundation

// MARK: - API Provider API 提供商

/// API 提供商配置模型
/// API provider configuration model
struct APIProvider: Codable, Identifiable, Equatable {
    /// 唯一标识符
    /// Unique identifier
    let id: UUID

    /// 提供商名称
    /// Provider name
    var name: String

    /// API 基础 URL
    /// API base URL
    var url: String

    /// API 密钥
    /// API key
    var key: String

    /// 大模型名称
    /// Large model name
    var largeModel: String?

    /// 小模型名称
    /// Small model name
    var smallModel: String?

    /// 所属分组名称
    /// Group name
    var groupName: String?

    /// 优先级（数字越小优先级越高）
    /// Priority (lower number = higher priority)
    var priority: Int

    enum CodingKeys: String, CodingKey {
        case id, name, url, key, largeModel, smallModel, groupName, priority
    }

    init(id: UUID = UUID(), name: String, url: String, key: String, largeModel: String? = nil, smallModel: String? = nil, groupName: String? = nil, priority: Int = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.key = key
        self.largeModel = largeModel
        self.smallModel = smallModel
        self.groupName = groupName
        self.priority = priority
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.url = try container.decode(String.self, forKey: .url)
        self.key = try container.decode(String.self, forKey: .key)
        self.largeModel = try container.decodeIfPresent(String.self, forKey: .largeModel)
        self.smallModel = try container.decodeIfPresent(String.self, forKey: .smallModel)
        self.groupName = try container.decodeIfPresent(String.self, forKey: .groupName)
        self.priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
    }

    /// 验证 API 密钥是否配置
    /// Validate if API configuration is complete
    var isValid: Bool {
        return !name.isEmpty && !url.isEmpty && !key.isEmpty
    }
}

// MARK: - Provider Group 分组模型
/// 提供商分组模型
/// Provider group model
struct ProviderGroup: Codable, Identifiable, Equatable {
    /// 代理池分组名称（从 AppConstants 获取）
    /// Proxy pool group name (from AppConstants)
    static let proxyGroupName = AppConstants.ProxyPool.name

    /// 代理池分组固定 ID（从 AppConstants 获取）
    /// Proxy pool group fixed ID (from AppConstants)
    static let proxyGroupID = AppConstants.ProxyPool.id

    let id: UUID
    var name: String
    var priority: Int
    var isBuiltin: Bool
    /// 代理池分组引用的服务商 ID 列表（仅代理池分组使用）
    /// Provider ID list referenced by proxy pool group (only used by proxy pool group)
    var providerRefs: [UUID]

    /// 是否为代理池分组
    /// Whether is proxy pool group
    var isProxyGroup: Bool {
        id == Self.proxyGroupID
    }

    init(id: UUID = UUID(), name: String, priority: Int = 0, isBuiltin: Bool = false, providerRefs: [UUID] = []) {
        self.id = id
        self.name = name
        self.priority = priority
        self.isBuiltin = isBuiltin
        self.providerRefs = providerRefs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        self.isBuiltin = try container.decodeIfPresent(Bool.self, forKey: .isBuiltin) ?? false
        self.providerRefs = try container.decodeIfPresent([UUID].self, forKey: .providerRefs) ?? []
    }

    /// 创建代理池分组
    /// Create proxy pool group
    static func createProxyGroup() -> ProviderGroup {
        ProviderGroup(id: proxyGroupID, name: proxyGroupName, priority: -1000, isBuiltin: true, providerRefs: [])
    }
}

// MARK: - Usage Stats 使用量统计

/// 使用量统计数据模型
/// Usage statistics data model
struct UsageStats: Codable {
    /// 总请求次数
    /// Total requests count
    let totalRequests: Int

    /// 总 Token 数
    /// Total tokens count
    let totalTokens: Int

    /// 费用
    /// Cost
    let cost: Double

    /// 日期
    /// Date
    let date: Date

    init(totalRequests: Int = 0, totalTokens: Int = 0, cost: Double = 0.0, date: Date = Date()) {
        self.totalRequests = totalRequests
        self.totalTokens = totalTokens
        self.cost = cost
        self.date = date
    }
}

// MARK: - Weekly Usage Stats 周统计汇总

/// 周统计汇总
/// Weekly usage statistics summary
struct WeeklyUsageStats {
    /// 总请求次数
    /// Total requests count
    let totalRequests: Int

    /// 总 Token 数
    /// Total tokens count
    let totalTokens: Int

    /// 总费用
    /// Total cost
    let totalCost: Double

    /// 每日统计数据
    /// Daily statistics
    let dailyStats: [UsageStats]

    /// 平均每日请求数
    /// Average requests per day
    let averageRequestsPerDay: Double

    /// 峰值日期
    /// Peak day
    let peakDay: Date?

    init(dailyStats: [UsageStats]) {
        self.dailyStats = dailyStats
        self.totalRequests = dailyStats.reduce(0) { $0 + $1.totalRequests }
        self.totalTokens = dailyStats.reduce(0) { $0 + $1.totalTokens }
        self.totalCost = dailyStats.reduce(0) { $0 + $1.cost }

        let daysCount = max(dailyStats.count, 1)
        self.averageRequestsPerDay = Double(totalRequests) / Double(daysCount)

        // 找到请求量最高的一天
        self.peakDay = dailyStats.max(by: { $0.totalRequests < $1.totalRequests })?.date
    }
}

// MARK: - Usage Metric Type 使用量类型

/// 使用量指标类型枚举
/// Usage metric type enumeration
enum UsageMetricType: CaseIterable {
    /// 请求次数
    /// Requests count
    case requests

    /// Token 使用量
    /// Tokens usage
    case tokens

    /// 费用
    /// Cost
    case cost

    /// 标题
    /// Title
    var title: String {
        switch self {
        case .requests:
            return "请求次数"
        case .tokens:
            return "Token使用"
        case .cost:
            return "费用"
        }
    }

    /// 单位
    /// Unit
    var unit: String {
        switch self {
        case .requests:
            return "次"
        case .tokens:
            return "tokens"
        case .cost:
            return "$"
        }
    }
}