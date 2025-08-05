import Foundation

// MARK: - Token 统计数据结构
struct TokenStatsData {
    var totalCost: Double = 0.0
    var totalTokens: Int = 0
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var totalCacheCreationTokens: Int = 0
    var totalCacheReadTokens: Int = 0
    var totalSessions: Int = 0
    var lastUpdated: Date? = nil
    
    static func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.2fM", Double(num) / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.1fK", Double(num) / 1_000)
        }
        return NumberFormatter.localizedString(from: NSNumber(value: num), number: .decimal)
    }
    
    static func formatCurrency(_ amount: Double) -> String {
        return String(format: "$%.4f", amount)
    }
}

// MARK: - JSONL 条目结构
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

// MARK: - Token 统计管理器
class TokenStatsManager: ObservableObject {
    static let shared = TokenStatsManager()
    
    @Published var statsData: TokenStatsData = TokenStatsData()
    @Published var isLoading: Bool = false
    @Published var lastUpdateTime: Date?
    
    private let claudePath: URL
    private let projectsPath: URL
    
    // Claude 模型价格表 (每百万 tokens)
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
    
    private struct ModelPricing {
        let input: Double
        let output: Double
        let cacheWrite: Double
        let cacheRead: Double
    }
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        claudePath = homeDir.appendingPathComponent(".claude")
        projectsPath = claudePath.appendingPathComponent("projects")
        
        // 启动时加载数据
        loadTokenStats()
    }
    
    // MARK: - 公共方法
    
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
    
    // MARK: - 私有方法
    
    private func loadTokenStats() {
        var newStats = TokenStatsData()
        
        guard claudeDirectoryExists() else {
            print("Claude directory not found, returning empty stats")
            DispatchQueue.main.async {
                self.statsData = newStats
            }
            return
        }
        
        do {
            let allEntries = try collectAllEntries()
            
            if allEntries.isEmpty {
                print("No usage entries found")
                DispatchQueue.main.async {
                    self.statsData = newStats
                }
                return
            }
            
            // 统计唯一会话数
            var uniqueSessions = Set<String>()
            
            // 累计统计
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
            
            print("Token stats: \(newStats.totalTokens) tokens, \(newStats.totalSessions) sessions, $\(String(format: "%.4f", newStats.totalCost)) cost")
            
            DispatchQueue.main.async {
                self.statsData = newStats
            }
            
        } catch {
            print("Failed to calculate token stats: \(error)")
            DispatchQueue.main.async {
                self.statsData = newStats
            }
        }
    }
    
    private func claudeDirectoryExists() -> Bool {
        var isDirectory: ObjCBool = false
        let claudeExists = FileManager.default.fileExists(atPath: claudePath.path, isDirectory: &isDirectory)
        let projectsExists = FileManager.default.fileExists(atPath: projectsPath.path, isDirectory: &isDirectory)
        return claudeExists && projectsExists && isDirectory.boolValue
    }
    
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
    
    private func calculateCost(model: String, inputTokens: Int, outputTokens: Int, cacheCreationTokens: Int, cacheReadTokens: Int) -> Double {
        let prices = getModelPrices(model)
        
        let cost = (Double(inputTokens) * prices.input / 1_000_000) +
                  (Double(outputTokens) * prices.output / 1_000_000) +
                  (Double(cacheCreationTokens) * prices.cacheWrite / 1_000_000) +
                  (Double(cacheReadTokens) * prices.cacheRead / 1_000_000)
        
        return cost
    }
}

// MARK: - 使用条目结构
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

// MARK: - 使用量统计适配器（保持与现有UI兼容）
extension TokenStatsManager {
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