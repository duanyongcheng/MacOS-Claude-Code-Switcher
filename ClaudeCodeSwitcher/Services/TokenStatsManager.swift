import Foundation

// MARK: - Token Stats Data Token 统计数据

/// Token 统计数据结构
/// Token statistics data structure
struct TokenStatsData {
    /// 总费用
    /// Total cost
    var totalCost: Double = 0.0

    /// 总 Token 数
    /// Total tokens count
    var totalTokens: Int = 0

    /// 输入 Token 数
    /// Input tokens count
    var totalInputTokens: Int = 0

    /// 输出 Token 数
    /// Output tokens count
    var totalOutputTokens: Int = 0

    /// 缓存创建 Token 数
    /// Cache creation tokens count
    var totalCacheCreationTokens: Int = 0

    /// 缓存读取 Token 数
    /// Cache read tokens count
    var totalCacheReadTokens: Int = 0

    /// 会话总数
    /// Total sessions count
    var totalSessions: Int = 0

    /// 最后更新时间
    /// Last updated time
    var lastUpdated: Date? = nil

    /// 格式化数字显示
    /// Format number for display
    static func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.2fM", Double(num) / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.1fK", Double(num) / 1_000)
        }
        return NumberFormatter.localizedString(from: NSNumber(value: num), number: .decimal)
    }

    /// 格式化货币显示
    /// Format currency for display
    static func formatCurrency(_ amount: Double) -> String {
        return String(format: "$%.4f", amount)
    }
}

// MARK: - Daily Stats Data 每日统计数据

/// 每日统计数据结构
/// Daily statistics data structure
struct DailyStatsData {
    /// 日期
    /// Date
    let date: Date

    /// 当日费用
    /// Cost for the day
    var cost: Double = 0.0

    /// 当日总 Token 数
    /// Total tokens for the day
    var totalTokens: Int = 0

    /// 当日输入 Token 数
    /// Input tokens for the day
    var inputTokens: Int = 0

    /// 当日输出 Token 数
    /// Output tokens for the day
    var outputTokens: Int = 0

    /// 当日缓存创建 Token 数
    /// Cache creation tokens for the day
    var cacheCreationTokens: Int = 0

    /// 当日缓存读取 Token 数
    /// Cache read tokens for the day
    var cacheReadTokens: Int = 0

    /// 当日会话集合
    /// Sessions set for the day
    var sessions: Set<String> = []

    /// 当日会话数量
    /// Session count for the day
    var sessionCount: Int {
        return sessions.count
    }

    /// 格式化日期（月/日）
    /// Format date (MM/dd)
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    /// 格式化完整日期（年-月-日）
    /// Format full date (yyyy-MM-dd)
    static func formatDateFull(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Recent Days Stats 最近几天统计

/// 最近几天的统计数据
/// Statistics for recent days
struct RecentDaysStats {
    /// 每日统计数据列表
    /// Daily statistics list
    let dailyStats: [DailyStatsData]

    /// 总体统计数据
    /// Overall statistics
    let totalStats: TokenStatsData

    init(dailyStats: [DailyStatsData], totalStats: TokenStatsData) {
        self.dailyStats = dailyStats
        self.totalStats = totalStats
    }
}

// MARK: - JSONL Entry JSONL 条目

/// JSONL 文件条目结构
/// JSONL file entry structure
struct JSONLEntry: Codable {
    let timestamp: String?
    let sessionId: String?
    let message: MessageData?
    let type: String?
    
    struct MessageData: Codable {
        let id: String?
        let model: String?
        let usage: UsageData?
        let role: String?
        
        struct UsageData: Codable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?
            
            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
            }
        }
    }
}

// MARK: - Token Stats Manager Token 统计管理器

/// Token 统计管理器
/// Manages token usage statistics from Claude conversation history
class TokenStatsManager: ObservableObject {
    // MARK: - Singleton

    static let shared = TokenStatsManager()

    // MARK: - Published Properties

    /// 统计数据
    /// Statistics data
    @Published var statsData: TokenStatsData = TokenStatsData()

    /// 最近几天的统计数据
    /// Recent days statistics
    @Published var recentDaysStats: RecentDaysStats?

    /// 是否正在加载
    /// Whether is loading
    @Published var isLoading: Bool = false

    /// 最后更新时间
    /// Last update time
    @Published var lastUpdateTime: Date?

    // MARK: - Private Properties

    /// Claude 目录路径
    /// Claude directory path
    private let claudePath: URL

    /// 项目目录路径
    /// Projects directory path
    private let projectsPath: URL

    // MARK: - Model Pricing 模型定价

    /// Claude 模型价格表（每百万 tokens）
    /// Claude model pricing table (per million tokens)
    private let modelPrices: [String: ModelPricing] = [
        // Claude 4 (更新价格)
        "claude-4-opus-20250514": ModelPricing(input: 15.0, output: 75.0, cacheWrite: 18.75, cacheRead: 1.50),
        "claude-opus-4-20250514": ModelPricing(input: 15.0, output: 75.0, cacheWrite: 18.75, cacheRead: 1.50),
        "claude-4-sonnet-20250514": ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30),
        "claude-sonnet-4-20250514": ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30),
        
        // 简化匹配模式
        "claude-4": ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30),
        "sonnet-4": ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30),
        "opus-4": ModelPricing(input: 15.0, output: 75.0, cacheWrite: 18.75, cacheRead: 1.50),
        
        // Claude 3.5
        "claude-3-5-sonnet": ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30),
        "claude-3.5-sonnet": ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30),
        "sonnet-3.5": ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30),
        "claude-3.5-haiku": ModelPricing(input: 0.80, output: 4.0, cacheWrite: 1.0, cacheRead: 0.08),
        "haiku-3.5": ModelPricing(input: 0.80, output: 4.0, cacheWrite: 1.0, cacheRead: 0.08),
        
        // Claude 3
        "claude-3-opus": ModelPricing(input: 15.0, output: 75.0, cacheWrite: 18.75, cacheRead: 1.50),
        "claude-3-sonnet": ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30),
        "claude-3-haiku": ModelPricing(input: 0.25, output: 1.25, cacheWrite: 0.30, cacheRead: 0.03)
    ]

    /// 模型定价结构
    /// Model pricing structure
    private struct ModelPricing {
        /// 输入价格（每百万 tokens 美元）
        /// Input price (USD per million tokens)
        let input: Double

        /// 输出价格（每百万 tokens 美元）
        /// Output price (USD per million tokens)
        let output: Double

        /// 缓存写入价格（每百万 tokens 美元）
        /// Cache write price (USD per million tokens)
        let cacheWrite: Double

        /// 缓存读取价格（每百万 tokens 美元）
        /// Cache read price (USD per million tokens)
        let cacheRead: Double
    }

    // MARK: - Initialization

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        claudePath = homeDir.appendingPathComponent(".claude")
        projectsPath = claudePath.appendingPathComponent("projects")

        // 启动时加载数据
        // Load data on initialization
        loadTokenStats()
    }

    // MARK: - Public Methods

    /// 刷新统计数据
    /// Refresh statistics data
    func refreshStats() {
        isLoading = true
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.loadTokenStats()
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.lastUpdateTime = Date()
            }
        }
    }

    // MARK: - Private Methods - Loading 加载

    /// 加载 Token 统计数据
    /// Load token statistics
    private func loadTokenStats() {
        var newStats = TokenStatsData()
        
        guard claudeDirectoryExists() else {
            print("Claude directory not found, returning empty stats")
            DispatchQueue.main.async {
                self.statsData = newStats
                self.recentDaysStats = nil
            }
            return
        }
        
        do {
            let allEntries = try collectAllEntries()
            
            if allEntries.isEmpty {
                print("No usage entries found")
                DispatchQueue.main.async {
                    self.statsData = newStats
                    self.recentDaysStats = nil
                }
                return
            }
            
            // 计算总体统计
            var uniqueSessions = Set<String>()
            
            for entry in allEntries {
                newStats.totalCost += entry.cost
                newStats.totalInputTokens += entry.inputTokens
                newStats.totalOutputTokens += entry.outputTokens
                newStats.totalCacheCreationTokens += entry.cacheCreationTokens
                newStats.totalCacheReadTokens += entry.cacheReadTokens
                
                uniqueSessions.insert(entry.sessionId)
            }
            
            newStats.totalTokens = newStats.totalInputTokens + newStats.totalOutputTokens +
                                  newStats.totalCacheCreationTokens + newStats.totalCacheReadTokens
            newStats.totalSessions = uniqueSessions.count
            newStats.lastUpdated = Date()
            
            // 计算最近3天的统计数据
            let recentStats = calculateRecentDaysStats(entries: allEntries, totalStats: newStats)
            
            print("Token stats: \(newStats.totalTokens) tokens, \(newStats.totalSessions) sessions, $\(String(format: "%.4f", newStats.totalCost)) cost")
            
            DispatchQueue.main.async {
                self.statsData = newStats
                self.recentDaysStats = recentStats
            }
            
        } catch {
            print("Failed to calculate token stats: \(error)")
            DispatchQueue.main.async {
                self.statsData = newStats
                self.recentDaysStats = nil
            }
        }
    }

    /// 检查 Claude 目录是否存在
    /// Check if Claude directory exists
    private func claudeDirectoryExists() -> Bool {
        var isDirectory: ObjCBool = false
        let claudeExists = FileManager.default.fileExists(atPath: claudePath.path, isDirectory: &isDirectory)
        let projectsExists = FileManager.default.fileExists(atPath: projectsPath.path, isDirectory: &isDirectory)
        return claudeExists && projectsExists && isDirectory.boolValue
    }

    /// 收集所有使用条目
    /// Collect all usage entries
    /// - Returns: 使用条目数组 / Usage entries array
    private func collectAllEntries() throws -> [UsageEntry] {
        var allEntries: [UsageEntry] = []
        
        let projectsContents = try FileManager.default.contentsOfDirectory(at: projectsPath, includingPropertiesForKeys: nil)
        
        for projectDir in projectsContents {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: projectDir.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                try scanDirectory(projectDir, entries: &allEntries)
            }
        }
        
        return allEntries
    }

    /// 扫描目录中的 JSONL 文件
    /// Scan directory for JSONL files
    /// - Parameters:
    ///   - dirURL: 目录 URL / Directory URL
    ///   - entries: 条目数组（引用传递）/ Entries array (passed by reference)
    private func scanDirectory(_ dirURL: URL, entries: inout [UsageEntry]) throws {
        let contents = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
        
        for item in contents {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // 递归扫描子目录
                    try scanDirectory(item, entries: &entries)
                } else if item.pathExtension == "jsonl" {
                    // 解析 JSONL 文件
                    let fileEntries = try parseJsonlFile(item)
                    entries.append(contentsOf: fileEntries)
                }
            }
        }
    }

    /// 解析 JSONL 文件
    /// Parse JSONL file
    /// - Parameter fileURL: 文件 URL / File URL
    /// - Returns: 使用条目数组 / Usage entries array
    private func parseJsonlFile(_ fileURL: URL) throws -> [UsageEntry] {
        var entries: [UsageEntry] = []
        
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var processedIds = Set<String>() // 用于去重
        
        for line in lines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            
            do {
                let jsonData = line.data(using: .utf8)!
                let jsonEntry = try JSONDecoder().decode(JSONLEntry.self, from: jsonData)
                
                // 只统计 assistant 类型的条目（包含实际的 token 使用信息）
                guard jsonEntry.type == "assistant",
                      let message = jsonEntry.message,
                      let usage = message.usage,
                      message.role == "assistant" else {
                    continue
                }
                
                let messageId = message.id ?? ""
                
                // 去重：避免重复统计同一条消息
                if !messageId.isEmpty && processedIds.contains(messageId) {
                    continue
                }
                if !messageId.isEmpty {
                    processedIds.insert(messageId)
                }
                
                let inputTokens = usage.inputTokens ?? 0
                let outputTokens = usage.outputTokens ?? 0
                let cacheCreationTokens = usage.cacheCreationInputTokens ?? 0
                let cacheReadTokens = usage.cacheReadInputTokens ?? 0
                
                // 跳过没有实际 token 使用的条目
                if inputTokens == 0 && outputTokens == 0 && cacheCreationTokens == 0 && cacheReadTokens == 0 {
                    continue
                }
                
                let model = message.model ?? "unknown"
                let sessionId = jsonEntry.sessionId ?? "unknown"
                
                let cost = calculateCost(
                    model: model,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheCreationTokens: cacheCreationTokens,
                    cacheReadTokens: cacheReadTokens
                )
                
                entries.append(UsageEntry(
                    timestamp: jsonEntry.timestamp ?? "",
                    model: model,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheCreationTokens: cacheCreationTokens,
                    cacheReadTokens: cacheReadTokens,
                    cost: cost,
                    sessionId: sessionId
                ))
                
            } catch {
                // 忽略解析错误的行
                continue
            }
        }
        
        return entries
    }

    // MARK: - Private Methods - Pricing 定价

    /// 获取模型定价
    /// Get model pricing
    /// - Parameter modelName: 模型名称 / Model name
    /// - Returns: 模型定价信息 / Model pricing info
    private func getModelPrices(_ modelName: String) -> ModelPricing {
        if modelName.isEmpty {
            return ModelPricing(input: 0.0, output: 0.0, cacheWrite: 0.0, cacheRead: 0.0)
        }
        
        let lowerModelName = modelName.lowercased()
        
        // 精确匹配优先
        if let pricing = modelPrices[lowerModelName] {
            return pricing
        }
        
        // 模糊匹配
        for (key, pricing) in modelPrices {
            if lowerModelName.contains(key) || key.contains(lowerModelName) {
                return pricing
            }
        }
        
        // 如果没有找到匹配的模型，返回默认价格（不输出警告以减少日志噪音）
        return ModelPricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30) // 使用 Sonnet 默认价格
    }

    /// 计算费用
    /// Calculate cost
    /// - Parameters:
    ///   - model: 模型名称 / Model name
    ///   - inputTokens: 输入 Token 数 / Input tokens
    ///   - outputTokens: 输出 Token 数 / Output tokens
    ///   - cacheCreationTokens: 缓存创建 Token 数 / Cache creation tokens
    ///   - cacheReadTokens: 缓存读取 Token 数 / Cache read tokens
    /// - Returns: 费用（美元）/ Cost (USD)
    private func calculateCost(model: String, inputTokens: Int, outputTokens: Int, cacheCreationTokens: Int, cacheReadTokens: Int) -> Double {
        let prices = getModelPrices(model)
        
        let cost = (Double(inputTokens) * prices.input / 1_000_000) +
                  (Double(outputTokens) * prices.output / 1_000_000) +
                  (Double(cacheCreationTokens) * prices.cacheWrite / 1_000_000) +
                  (Double(cacheReadTokens) * prices.cacheRead / 1_000_000)
        
        return cost
    }

    /// 计算最近几天的统计数据
    /// Calculate recent days statistics
    /// - Parameters:
    ///   - entries: 所有使用条目 / All usage entries
    ///   - totalStats: 总体统计数据 / Total statistics
    /// - Returns: 最近几天的统计 / Recent days statistics
    private func calculateRecentDaysStats(entries: [UsageEntry], totalStats: TokenStatsData) -> RecentDaysStats {
        let calendar = Calendar.current
        let today = Date()
        
        // 创建最近3天的日期（今天、昨天、前天）
        var dailyStatsDict: [String: DailyStatsData] = [:]
        
        for i in 0..<3 {
            let date = calendar.date(byAdding: .day, value: -i, to: today) ?? today
            let dateKey = DailyStatsData.formatDateFull(date)
            dailyStatsDict[dateKey] = DailyStatsData(date: date)
        }
        
        // 按日期分组统计数据
        for entry in entries {
            let entryDate = parseTimestamp(entry.timestamp)
            let dateKey = DailyStatsData.formatDateFull(entryDate)
            
            if var dayStats = dailyStatsDict[dateKey] {
                dayStats.cost += entry.cost
                dayStats.inputTokens += entry.inputTokens
                dayStats.outputTokens += entry.outputTokens
                dayStats.cacheCreationTokens += entry.cacheCreationTokens
                dayStats.cacheReadTokens += entry.cacheReadTokens
                dayStats.totalTokens = dayStats.inputTokens + dayStats.outputTokens + 
                                      dayStats.cacheCreationTokens + dayStats.cacheReadTokens
                dayStats.sessions.insert(entry.sessionId)
                
                dailyStatsDict[dateKey] = dayStats
            }
        }
        
        // 转换为排序的数组（最新的日期在前）
        let sortedDailyStats = dailyStatsDict.values.sorted { $0.date > $1.date }
        
        return RecentDaysStats(dailyStats: sortedDailyStats, totalStats: totalStats)
    }

    /// 解析时间戳
    /// Parse timestamp string
    /// - Parameter timestamp: 时间戳字符串 / Timestamp string
    /// - Returns: 日期对象 / Date object
    private func parseTimestamp(_ timestamp: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: timestamp) {
            return date
        }
        
        // 备用解析器
        let backupFormatter = DateFormatter()
        backupFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        backupFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        return backupFormatter.date(from: timestamp) ?? Date()
    }
}

// MARK: - Usage Entry 使用条目

/// 使用条目结构（私有）
/// Usage entry structure (private)
private struct UsageEntry {
    let timestamp: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let cost: Double
    let sessionId: String
}

// MARK: - Weekly Stats Adapter 周统计适配器

/// 使用量统计适配器（保持与现有 UI 兼容）
/// Usage statistics adapter (maintains compatibility with existing UI)
extension TokenStatsManager {
    /// 周统计数据（适配器）
    /// Weekly statistics (adapter)
    var weeklyStats: WeeklyUsageStats? {
        guard statsData.totalTokens > 0 else { return nil }
        
        // 创建一个总计统计项
        let totalStats = UsageStats(
            totalRequests: statsData.totalSessions, // 使用会话数作为请求数
            totalTokens: statsData.totalTokens,
            cost: statsData.totalCost,
            date: Date()
        )
        
        return WeeklyUsageStats(dailyStats: [totalStats])
    }
}