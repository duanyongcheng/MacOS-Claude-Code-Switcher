import SwiftUI
import AppKit
import Foundation

struct SettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @StateObject private var tokenStatsManager = TokenStatsManager.shared
    @State private var showingAddProvider = false
    @State private var editingProvider: APIProvider?
    @State private var claudeProcessStatus: String = "未检测到"
    @State private var balanceStatus: BalanceStatus = .idle
    @State private var selectedBalanceProvider: APIProvider?
    private let balanceService = BalanceService()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 当前配置卡片
                CurrentConfigCard(
                    currentProvider: configManager.currentProvider,
                    selectedBalanceProvider: selectedBalanceProvider,
                    balanceStatus: balanceStatus,
                    processStatus: claudeProcessStatus
                )
                
                // 使用量统计卡片
                UsageStatsCard(
                    balanceStatus: balanceStatus,
                    providers: configManager.providers,
                    selectedProvider: $selectedBalanceProvider,
                    onBalanceRefresh: { provider in
                        refreshBalance(for: provider)
                    },
                    recentDaysStats: tokenStatsManager.recentDaysStats,
                    isLoading: tokenStatsManager.isLoading,
                    lastUpdateTime: tokenStatsManager.lastUpdateTime,
                    onRefresh: {
                        tokenStatsManager.refreshStats()
                    }
                )
                
                // 可用配置列表
                AvailableConfigsCard(
                    providers: configManager.providers,
                    currentProvider: configManager.currentProvider,
                    selectedBalanceProvider: selectedBalanceProvider,
                    balanceStatus: balanceStatus,
                    onEdit: { provider in
                        editingProvider = provider
                    },
                    onDelete: { provider in
                        configManager.removeProvider(provider)
                    },
                    onCopy: { provider in
                        configManager.copyProvider(provider)
                    },
                    onSelect: { provider in
                        configManager.setCurrentProvider(provider)
                    }
                )
                
                // Claude 进程监控
                ClaudeProcessCard(status: claudeProcessStatus)
                
                // 代理设置
                ProxySettingsCard(
                    proxyHost: $configManager.proxyHost,
                    proxyPort: $configManager.proxyPort,
                    autoStartup: $configManager.autoStartup,
                    onSave: {
                        configManager.updateGlobalSettings(
                            autoUpdate: configManager.autoUpdate,
                            proxyHost: configManager.proxyHost,
                            proxyPort: configManager.proxyPort,
                            autoStartup: configManager.autoStartup
                        )
                    }
                )
                
                // 底部操作按钮
                ActionButtonsCard(
                    onAddProvider: {
                        showingAddProvider = true
                    },
                    onRefresh: {
                        checkClaudeProcess()
                    }
                )
            }
            .padding(20)
        }
        .background(Color(.windowBackgroundColor))
        .frame(width: 500, height: 700)
        .onAppear {
            print("=== SettingsView onAppear 被调用 ===")
            print("=== 当前 configManager.providers 数量: \(configManager.providers.count) ===")
            configManager.reloadConfiguration()
            checkClaudeProcess()
            selectedBalanceProvider = configManager.currentProvider
            refreshBalance(for: selectedBalanceProvider)
        }
        .sheet(isPresented: $showingAddProvider) {
            AddProviderView { provider in
                configManager.addProvider(provider)
            }
        }
        .sheet(item: $editingProvider) { provider in
            EditProviderView(provider: provider) { updatedProvider in
                configManager.updateProvider(updatedProvider)
            }
        }
        .onChange(of: configManager.currentProvider?.id) { newValue in
            if selectedBalanceProvider == nil || selectedBalanceProvider?.id == nil || selectedBalanceProvider?.id == newValue {
                selectedBalanceProvider = configManager.currentProvider
            }
        }
    }
    
    private func refreshBalance(for provider: APIProvider?) {
        guard let provider else {
            balanceStatus = .failure(message: "请选择配置")
            return
        }
        
        balanceStatus = .loading
        
        balanceService.fetchBalance(for: provider) { result in
            switch result {
            case .success(let balance):
                let tokensInt = balance.availableTokens
                let tokens = Double(tokensInt)
                let dollars = tokens / 500_000.0
                let now = Date()
                print("余额查询成功，available tokens: \(tokensInt), totalGranted: \(balance.totalGranted ?? -1), totalUsed: \(balance.totalUsed ?? -1), 折合美元: \(dollars)")
                DispatchQueue.main.async {
                    balanceStatus = .success(
                        amount: dollars,
                        currency: "$",
                        updatedAt: now,
                        provider: provider,
                        tokens: tokensInt
                    )
                    
                    NotificationCenter.default.post(
                        name: .balanceDidUpdate,
                        object: nil,
                        userInfo: [
                            "providerId": provider.id.uuidString,
                            "providerName": provider.name,
                            "tokens": tokensInt,
                            "dollars": dollars
                        ]
                    )
                }
            case .failure(let error):
                print("余额查询失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    balanceStatus = .failure(message: error.localizedDescription)
                    
                    NotificationCenter.default.post(
                        name: .balanceDidUpdate,
                        object: nil,
                        userInfo: [
                            "providerId": provider.id.uuidString,
                            "providerName": provider.name,
                            "error": error.localizedDescription
                        ]
                    )
                }
            }
        }
    }
    
    private func checkClaudeProcess() {
        // 检查 Claude 进程状态的逻辑
        claudeProcessStatus = "正在检查..."
        
        DispatchQueue.global().async {
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", "pgrep -f claude"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            task.launch()
            task.waitUntilExit()
            
            DispatchQueue.main.async {
                if task.terminationStatus == 0 {
                    claudeProcessStatus = "运行中"
                } else {
                    claudeProcessStatus = "未运行"
                }
            }
        }
    }
}

// MARK: - 余额状态
enum BalanceStatus: Equatable {
    case idle
    case loading
    case success(amount: Double, currency: String, updatedAt: Date?, provider: APIProvider, tokens: Int?)
    case failure(message: String)
    
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
    
    var formattedAmount: String {
        switch self {
        case .success(let amount, let currency, _, _, _):
            if currency == "tok" {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 0
                let tokenText = formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
                return "剩余 \(tokenText) token"
            } else if currency == "$" {
                return "$" + String(format: "%.2f", amount)
            }
            return "\(currency)\(String(format: "%.2f", amount))"
        default:
            return "--"
        }
    }
    
    var detailText: String {
        switch self {
        case .idle:
            return "未查询余额"
        case .loading:
            return "查询中..."
        case .success(_, let currency, let updatedAt, _, let tokens):
            var parts: [String] = []
            if currency == "$", let tokens = tokens {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 0
                let tokenText = formatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
                parts.append("剩余 \(tokenText) token")
            }
            if let updatedAt = updatedAt {
                parts.append("更新于 \(DateFormatter.shortTimeFormatter.string(from: updatedAt))")
            }
            return parts.isEmpty ? "已更新" : parts.joined(separator: " · ")
        case .failure(let message):
            return "获取失败：\(message)"
        }
    }
    
    var highlightColor: Color {
        switch self {
        case .success(let amount, let currency, _, _, _):
            if currency == "tok" {
                return .blue
            }
            return amount < 5.0 ? .orange : .green
        case .failure:
            return .orange
        default:
            return .secondary
        }
    }
    
    var compactLabel: String {
        switch self {
        case .success:
            return "余额 \(formattedAmount)"
        case .loading:
            return "余额查询中"
        case .failure:
            return "余额获取失败"
        case .idle:
            return "余额未查询"
        }
    }
}

extension DateFormatter {
    static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - 使用量统计卡片
struct UsageStatsCard: View {
    let balanceStatus: BalanceStatus
    let providers: [APIProvider]
    @Binding var selectedProvider: APIProvider?
    let onBalanceRefresh: (APIProvider?) -> Void
    let recentDaysStats: RecentDaysStats?
    let isLoading: Bool
    let lastUpdateTime: Date?
    let onRefresh: () -> Void
    
    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                BalanceSummaryRow(
                    status: balanceStatus,
                    providers: providers,
                    selectedProvider: $selectedProvider,
                    onRefresh: onBalanceRefresh
                )
                
                Divider()
                
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    Text("使用量统计")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("刷新") {
                            onRefresh()
                        }
                        .buttonStyle(CompactButtonStyle(color: .blue))
                    }
                }
                
                if let stats = recentDaysStats {
                    VStack(spacing: 16) {
                        // 总计统计卡片
                        VStack(alignment: .leading, spacing: 12) {
                            Text("全部用量统计")
                                .font(.subheadline)
                                .font(Font.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 12) {
                                StatsCardView(
                                    title: "总费用",
                                    value: TokenStatsData.formatCurrency(stats.totalStats.totalCost),
                                    icon: "dollarsign.circle.fill",
                                    color: .orange
                                )
                                
                                StatsCardView(
                                    title: "会话数",
                                    value: "\(stats.totalStats.totalSessions)",
                                    icon: "bubble.left.and.bubble.right.fill",
                                    color: .blue
                                )
                                
                                StatsCardView(
                                    title: "Token总数",
                                    value: TokenStatsData.formatNumber(stats.totalStats.totalTokens),
                                    icon: "textformat.abc",
                                    color: .green
                                )
                            }
                        }
                        
                        Divider()
                        
                        // 最近三天详情
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(.blue)
                                    .font(.subheadline)
                                Text("最近3天趋势")
                                    .font(.subheadline)
                                    .font(Font.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            
                            // 三天卡片横向布局
                            HStack(spacing: 8) {
                                ForEach(stats.dailyStats, id: \.date) { dayStats in
                                    VStack(spacing: 8) {
                                        // 日期标题
                                        VStack(spacing: 2) {
                                            if Calendar.current.isDateInToday(dayStats.date) {
                                                Text("今天")
                                                    .font(.caption)
                                                    .font(Font.caption.weight(.semibold))
                                                    .foregroundColor(.blue)
                                            } else if Calendar.current.isDateInYesterday(dayStats.date) {
                                                Text("昨天")
                                                    .font(.caption)
                                                    .font(Font.caption.weight(.semibold))
                                                    .foregroundColor(.secondary)
                                            } else {
                                                Text("前天")
                                                    .font(.caption)
                                                    .font(Font.caption.weight(.semibold))
                                                    .foregroundColor(.secondary)
                                            }
                                            Text(DailyStatsData.formatDate(dayStats.date))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Divider()
                                            .padding(.horizontal, 4)
                                        
                                        // 数据内容
                                        VStack(alignment: .leading, spacing: 6) {
                                            // 会话数
                                            HStack(spacing: 4) {
                                                Image(systemName: "bubble.left.and.bubble.right")
                                                    .font(.caption2)
                                                    .foregroundColor(.blue)
                                                Text("\(dayStats.sessionCount)")
                                                    .font(.caption)
                                                    .font(Font.caption.weight(.medium))
                                                Text("会话")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            // Token数
                                            HStack(spacing: 4) {
                                                Image(systemName: "textformat")
                                                    .font(.caption2)
                                                    .foregroundColor(.green)
                                                Text(formatCompactNumber(dayStats.totalTokens))
                                                    .font(.caption)
                                                    .font(Font.caption.weight(.medium))
                                                Text("Token")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            // 费用
                                            HStack(spacing: 4) {
                                                Image(systemName: "dollarsign.circle")
                                                    .font(.caption2)
                                                    .foregroundColor(.orange)
                                                Text(TokenStatsData.formatCurrency(dayStats.cost))
                                                    .font(.caption)
                                                    .font(Font.caption.weight(.medium))
                                            }
                                        }
                                        
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(dayStats.totalTokens > 0 ? 
                                                (Calendar.current.isDateInToday(dayStats.date) ? 
                                                    Color.blue.opacity(0.1) : 
                                                    Color(.controlBackgroundColor)) : 
                                                Color(.controlBackgroundColor).opacity(0.5))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                Calendar.current.isDateInToday(dayStats.date) && dayStats.totalTokens > 0 ? 
                                                    Color.blue.opacity(0.3) : 
                                                    Color.clear, 
                                                lineWidth: 1
                                            )
                                    )
                                }
                            }
                            .frame(height: 120)
                        }
                        
                        // 更新时间
                        if let updateTime = lastUpdateTime {
                            HStack {
                                Spacer()
                                Text("更新时间: \(formatTime(updateTime))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        Text("暂无使用量数据")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("点击刷新按钮从 Claude 日志中加载实际使用数据")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func formatCompactNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
}

struct BalanceSummaryRow: View {
    let status: BalanceStatus
    let providers: [APIProvider]
    @Binding var selectedProvider: APIProvider?
    let onRefresh: (APIProvider?) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "wallet.pass.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("账户余额")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Text(status.detailText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    if status.isLoading {
                        ProgressView()
                            .scaleEffect(0.9)
                    } else {
                        Text(status.formattedAmount)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(status.highlightColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(status.highlightColor.opacity(0.1))
                            )
                    }
                    
                    Button("查询余额") {
                        onRefresh(selectedProvider)
                    }
                    .buttonStyle(CompactButtonStyle(color: .orange))
                    .disabled(status.isLoading || selectedProvider == nil)
                }
            }
            
            HStack(spacing: 12) {
                Menu {
                    if providers.isEmpty {
                        Text("暂无配置")
                    } else {
                        ForEach(providers) { provider in
                            Button(provider.name) {
                                selectedProvider = provider
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        Text(selectedProvider?.name ?? "选择配置")
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
                }
                .menuStyle(BorderlessButtonMenuStyle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("配置地址")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(selectedProvider?.url ?? "请选择需要查询余额的配置")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.textBackgroundColor))
        )
    }
}

// MARK: - 统计卡片视图
struct StatsCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.title2)
                    .font(Font.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - 详情行视图
struct DetailRowView: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .font(Font.subheadline.weight(.medium))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - 当前配置卡片
struct CurrentConfigCard: View {
    let currentProvider: APIProvider?
    let selectedBalanceProvider: APIProvider?
    let balanceStatus: BalanceStatus
    let processStatus: String
    
    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    
                    Text("当前配置")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    StatusBadge(status: processStatus)
                }
                
                if let provider = currentProvider {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(provider.name)
                                .font(.title3)
                                .font(Font.body.weight(.semibold))
                            
                            Text(provider.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            if let model = provider.largeModel {
                                Label("模型: \(model)", systemImage: "brain")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // 连接状态指示器
                        VStack(spacing: 6) {
                            Circle()
                                .fill(provider.isValid ? Color.green : Color.red)
                                .frame(width: 12, height: 12)
                            
                            Text(provider.isValid ? "已配置" : "配置错误")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text(balanceStatus.compactLabel)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            
                            if let selectedBalanceProvider {
                                Text("余额查询: \(selectedBalanceProvider.name)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "gear.badge.questionmark")
                            .foregroundColor(.orange)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("未选择配置")
                                .font(.subheadline)
                                .font(Font.subheadline.weight(.medium))
                            
                            Text("请在下方选择或添加配置")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - 可用配置列表卡片
struct AvailableConfigsCard: View {
    let providers: [APIProvider]
    let currentProvider: APIProvider?
    let selectedBalanceProvider: APIProvider?
    let balanceStatus: BalanceStatus
    let onEdit: (APIProvider) -> Void
    let onDelete: (APIProvider) -> Void
    let onCopy: (APIProvider) -> Void
    let onSelect: (APIProvider) -> Void
    
    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    Text("可用配置")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // 配置数量标识
                    Text("\(providers.count)")
                        .font(.caption)
                        .font(Font.subheadline.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.2))
                        )
                        .foregroundColor(.blue)
                }
                
                if providers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        Text("暂无配置")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("点击下方\"添加配置\"按钮开始使用")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(providers) { provider in
                            ProviderRowView(
                                provider: provider,
                                isCurrent: provider.id == currentProvider?.id,
                                isBalanceTarget: provider.id == selectedBalanceProvider?.id,
                                balanceStatus: balanceStatus,
                                onEdit: onEdit,
                                onDelete: onDelete,
                                onCopy: onCopy,
                                onSelect: onSelect
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 提供商行视图
struct ProviderRowView: View {
    let provider: APIProvider
    let isCurrent: Bool
    let isBalanceTarget: Bool
    let balanceStatus: BalanceStatus
    let onEdit: (APIProvider) -> Void
    let onDelete: (APIProvider) -> Void
    let onCopy: (APIProvider) -> Void
    let onSelect: (APIProvider) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 状态指示器
            VStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                
                if isCurrent {
                    Text("当前")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .frame(width: 30)
            
            // 主要信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(provider.name)
                        .font(.subheadline)
                        .font(Font.subheadline.weight(.medium))
                        .foregroundColor(isCurrent ? .green : .primary)
                    
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    
                    if !provider.isValid {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                
                Text(provider.url)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let model = provider.largeModel {
                    Text("主模型: \(model)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "wallet.pass")
                        .foregroundColor(balanceDisplay.color)
                        .font(.caption2)
                    Text(balanceDisplay.text)
                        .font(.caption2)
                        .foregroundColor(balanceDisplay.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 6) {
                if !isCurrent && provider.isValid {
                    Button("选择") {
                        onSelect(provider)
                    }
                    .buttonStyle(CompactButtonStyle(color: .green))
                }
                
                Button("复制") {
                    onCopy(provider)
                }
                .buttonStyle(CompactButtonStyle(color: .purple))
                
                Button("编辑") {
                    onEdit(provider)
                }
                .buttonStyle(CompactButtonStyle(color: .blue))
                
                Button("删除") {
                    onDelete(provider)
                }
                .buttonStyle(CompactButtonStyle(color: .red))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.green.opacity(0.1) : Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    private var statusColor: Color {
        if isCurrent {
            return .green
        } else if provider.isValid {
            return .blue
        } else {
            return .orange
        }
    }
    
    private var balanceDisplay: (text: String, color: Color) {
        guard isBalanceTarget else {
            return ("余额: --", .secondary)
        }
        
        switch balanceStatus {
        case .loading:
            return ("余额: 查询中...", .secondary)
        case .success(let amount, let currency, _, _, _):
            let color: Color = amount < 5.0 ? .orange : .green
            return ("余额: \(currency)\(String(format: "%.2f", amount))", color)
        case .failure:
            return ("余额: 获取失败", .orange)
        case .idle:
            return ("余额: 未查询", .secondary)
        }
    }
}

// MARK: - Claude 进程监控卡片
struct ClaudeProcessCard: View {
    let status: String
    
    var body: some View {
        CardView {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude 进程状态")
                        .font(.headline)
                    
                    Text(status)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                StatusBadge(status: status)
            }
        }
    }
}

// MARK: - 代理设置卡片
struct ProxySettingsCard: View {
    @Binding var proxyHost: String
    @Binding var proxyPort: String
    @Binding var autoStartup: Bool
    let onSave: () -> Void
    @ObservedObject private var configManager = ConfigManager.shared
    @State private var launchAgentStatus: Bool = false
    
    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                Text("应用设置")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // 开机自启动设置
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "power")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("开机自动启动")
                                .font(.subheadline)
                                .font(Font.subheadline.weight(.medium))
                            
                            Text("启用后应用将在系统启动时自动运行")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $autoStartup)
                            .toggleStyle(SwitchToggleStyle())
                    }
                    
                    // 显示 Launch Agent 状态
                    if autoStartup {
                        HStack {
                            Image(systemName: launchAgentStatus ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(launchAgentStatus ? .green : .orange)
                                .font(.caption)
                            
                            Text(launchAgentStatus ? "Launch Agent 已正确安装" : "Launch Agent 未正确安装，点击保存修复")
                                .font(.caption)
                                .foregroundColor(launchAgentStatus ? .green : .orange)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(launchAgentStatus ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        )
                    }
                }
                
                Divider()
                
                // 代理设置标题
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    Text("代理设置")
                        .font(.subheadline)
                        .font(Font.subheadline.weight(.medium))
                }
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("服务器地址")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("代理服务器", text: $proxyHost)
                            .textFieldStyle(ModernTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("端口")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("端口", text: $proxyPort)
                            .textFieldStyle(ModernTextFieldStyle())
                            .frame(width: 80)
                    }
                }
                
                Button("保存设置") {
                    onSave()
                    // 保存后稍等再检测一次 Launch Agent 状态并更新界面
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        launchAgentStatus = configManager.checkLaunchAgentStatus()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .onAppear {
            // 初始展示 Launch Agent 安装状态
            launchAgentStatus = configManager.checkLaunchAgentStatus()
        }
        .onChange(of: autoStartup) { _ in
            // 开关变化时，稍后刷新一次状态显示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                launchAgentStatus = configManager.checkLaunchAgentStatus()
            }
        }
    }
}

// MARK: - 操作按钮卡片
struct ActionButtonsCard: View {
    let onAddProvider: () -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button("添加配置") {
                onAddProvider()
            }
            .buttonStyle(PrimaryButtonStyle())
            
            Button("刷新状态") {
                onRefresh()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

// MARK: - 通用组件

struct CardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
    }
}

struct StatusBadge: View {
    let status: String
    
    private var badgeColor: Color {
        switch status {
        case "运行中":
            return .green
        case "未运行":
            return .red
        case "正在检查...":
            return .orange
        default:
            return .gray
        }
    }
    
    var body: some View {
        Text(status)
            .font(.caption)
            .font(Font.subheadline.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(badgeColor.opacity(0.2))
            )
            .foregroundColor(badgeColor)
    }
}

// MARK: - 自定义按钮样式

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .font(Font.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .foregroundColor(.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CompactButtonStyle: ButtonStyle {
    let color: Color
    
    init(color: Color = .accentColor) {
        self.color = color
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.1))
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .foregroundColor(color)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
            )
    }
}

// MARK: - 添加和编辑提供商视图 (使用新样式)

struct AddProviderView: View {
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var key: String = ""
    @State private var largeModel: String = ""
    @State private var smallModel: String = ""
    @Environment(\.dismiss) private var dismiss
    
    let onAdd: (APIProvider) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("添加 API 提供商")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("名称")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("输入提供商名称", text: $name)
                        .textFieldStyle(ModernTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("API URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("输入 API 地址", text: $url)
                        .textFieldStyle(ModernTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("API 密钥")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("输入 API 密钥", text: $key)
                        .textFieldStyle(ModernTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("大模型（可选）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("如：claude-3-opus-20240229", text: $largeModel)
                        .textFieldStyle(ModernTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("小模型（可选）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("如：claude-3-haiku-20240307", text: $smallModel)
                        .textFieldStyle(ModernTextFieldStyle())
                }
            }
            
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("添加") {
                    let provider = APIProvider(
                        name: name,
                        url: url,
                        key: key,
                        largeModel: largeModel.isEmpty ? nil : largeModel,
                        smallModel: smallModel.isEmpty ? nil : smallModel
                    )
                    onAdd(provider)
                    dismiss()
                }
                .disabled(name.isEmpty || url.isEmpty || key.isEmpty)
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 450, height: 500)
        .background(Color(.windowBackgroundColor))
    }
}

struct EditProviderView: View {
    @State private var name: String
    @State private var url: String
    @State private var key: String
    @State private var largeModel: String
    @State private var smallModel: String
    @Environment(\.dismiss) private var dismiss
    
    let provider: APIProvider
    let onUpdate: (APIProvider) -> Void
    
    init(provider: APIProvider, onUpdate: @escaping (APIProvider) -> Void) {
        self.provider = provider
        self.onUpdate = onUpdate
        self._name = State(initialValue: provider.name)
        self._url = State(initialValue: provider.url)
        self._key = State(initialValue: provider.key)
        self._largeModel = State(initialValue: provider.largeModel ?? "")
        self._smallModel = State(initialValue: provider.smallModel ?? "")
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("编辑 API 提供商")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("名称")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("输入提供商名称", text: $name)
                        .textFieldStyle(ModernTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("API URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("输入 API 地址", text: $url)
                        .textFieldStyle(ModernTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("API 密钥")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("输入 API 密钥", text: $key)
                        .textFieldStyle(ModernTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("大模型（可选）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("如：claude-3-opus-20240229", text: $largeModel)
                        .textFieldStyle(ModernTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("小模型（可选）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("如：claude-3-haiku-20240307", text: $smallModel)
                        .textFieldStyle(ModernTextFieldStyle())
                }
            }
            
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("保存") {
                    var updatedProvider = provider
                    updatedProvider.name = name
                    updatedProvider.url = url
                    updatedProvider.key = key
                    updatedProvider.largeModel = largeModel.isEmpty ? nil : largeModel
                    updatedProvider.smallModel = smallModel.isEmpty ? nil : smallModel
                    onUpdate(updatedProvider)
                    dismiss()
                }
                .disabled(name.isEmpty || url.isEmpty || key.isEmpty)
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 450, height: 500)
        .background(Color(.windowBackgroundColor))
    }
}
