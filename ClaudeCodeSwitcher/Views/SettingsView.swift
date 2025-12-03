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
            VStack(spacing: 16) {
                CurrentConfigCard(
                    currentProvider: configManager.currentProvider,
                    processStatus: claudeProcessStatus
                )

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

                AvailableConfigsCard(
                    providers: configManager.providers,
                    currentProvider: configManager.currentProvider,
                    providerGroups: configManager.providerGroups,
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
                    },
                    onAddProvider: {
                        showingAddProvider = true
                    },
                    onAddGroup: { name in
                        configManager.addGroup(name)
                    },
                    onDeleteGroup: { name in
                        configManager.removeGroup(name)
                    },
                    onUpdateGroup: { group in
                        configManager.updateGroup(group)
                    },
                    onMoveToGroup: { provider, groupName in
                        var updated = provider
                        updated.groupName = groupName
                        configManager.updateProvider(updated)
                    }
                )

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
                    },
                    onRefresh: {
                        checkClaudeProcess()
                    }
                )
            }
            .padding(16)
        }
        .background(Color(.windowBackgroundColor))
        .frame(minWidth: 480, idealWidth: 520, minHeight: 600, idealHeight: 680)
        .onAppear {
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
            VStack(alignment: .leading, spacing: 14) {
                BalanceSummaryRow(
                    status: balanceStatus,
                    providers: providers,
                    selectedProvider: $selectedProvider,
                    onRefresh: onBalanceRefresh
                )

                Divider()

                HStack {
                    Text("使用量统计")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button("刷新") {
                            onRefresh()
                        }
                        .buttonStyle(CompactButtonStyle(color: .blue))
                    }
                }

                if let stats = recentDaysStats {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            MiniStatsCard(
                                title: "总费用",
                                value: TokenStatsData.formatCurrency(stats.totalStats.totalCost),
                                color: .orange
                            )

                            MiniStatsCard(
                                title: "会话数",
                                value: "\(stats.totalStats.totalSessions)",
                                color: .blue
                            )

                            MiniStatsCard(
                                title: "Token",
                                value: TokenStatsData.formatNumber(stats.totalStats.totalTokens),
                                color: .green
                            )
                        }

                        HStack(spacing: 6) {
                            ForEach(stats.dailyStats, id: \.date) { dayStats in
                                DayStatsMini(dayStats: dayStats)
                            }
                        }

                        if let updateTime = lastUpdateTime {
                            HStack {
                                Spacer()
                                Text("更新于 \(formatTime(updateTime))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text("暂无数据，点击刷新")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct MiniStatsCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.1))
        )
    }
}

struct DayStatsMini: View {
    let dayStats: DailyStatsData

    private var dayLabel: String {
        if Calendar.current.isDateInToday(dayStats.date) {
            return "今天"
        } else if Calendar.current.isDateInYesterday(dayStats.date) {
            return "昨天"
        } else {
            return "前天"
        }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(dayStats.date)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayLabel)
                .font(.caption2)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundColor(isToday ? .blue : .secondary)

            Text(TokenStatsData.formatCurrency(dayStats.cost))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isToday ? Color.blue.opacity(0.1) : Color(.controlBackgroundColor))
        )
    }
}

struct BalanceSummaryRow: View {
    let status: BalanceStatus
    let providers: [APIProvider]
    @Binding var selectedProvider: APIProvider?
    let onRefresh: (APIProvider?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("账户余额")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if status.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text(status.formattedAmount)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(status.highlightColor)
                }
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(providers) { provider in
                        Button(provider.name) {
                            selectedProvider = provider
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedProvider?.name ?? "选择配置")
                            .font(.caption)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)

                Spacer()

                Button("查询") {
                    onRefresh(selectedProvider)
                }
                .buttonStyle(CompactButtonStyle(color: .orange))
                .disabled(status.isLoading || selectedProvider == nil)
            }

            Text(status.detailText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.textBackgroundColor))
        )
    }
}

// MARK: - 当前配置卡片
struct CurrentConfigCard: View {
    let currentProvider: APIProvider?
    let processStatus: String

    var body: some View {
        CardView {
            HStack(spacing: 12) {
                if let provider = currentProvider {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(provider.isValid ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)

                            Text(provider.name)
                                .font(.headline)

                            Spacer()

                            StatusBadge(status: processStatus)
                        }

                        Text(provider.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        if let model = provider.largeModel {
                            Text(model)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "gear.badge.questionmark")
                            .foregroundColor(.orange)

                        Text("未选择配置")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        StatusBadge(status: processStatus)
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
    let providerGroups: [ProviderGroup]
    let onEdit: (APIProvider) -> Void
    let onDelete: (APIProvider) -> Void
    let onCopy: (APIProvider) -> Void
    let onSelect: (APIProvider) -> Void
    let onAddProvider: () -> Void
    let onAddGroup: (String) -> Void
    let onDeleteGroup: (String) -> Void
    let onUpdateGroup: (ProviderGroup) -> Void
    let onMoveToGroup: (APIProvider, String?) -> Void

    @State private var showingAddGroup = false
    @State private var newGroupName = ""
    @State private var collapsedGroups: Set<String> = []
    @State private var editingGroup: ProviderGroup?

    private var groups: [String] {
        providerGroups.sorted { $0.priority < $1.priority }.map { $0.name }
    }

    private func groupedProviders() -> [(group: ProviderGroup?, providers: [APIProvider])] {
        var result: [(group: ProviderGroup?, providers: [APIProvider])] = []

        let sortedGroups = providerGroups.sorted { $0.priority < $1.priority }
        for group in sortedGroups {
            let groupProviders = providers.filter { $0.groupName == group.name }.sorted { $0.priority < $1.priority }
            result.append((group: group, providers: groupProviders))
        }

        let ungrouped = providers.filter { $0.groupName == nil || $0.groupName?.isEmpty == true }.sorted { $0.priority < $1.priority }
        if !ungrouped.isEmpty || sortedGroups.isEmpty {
            result.append((group: nil, providers: ungrouped))
        }

        return result
    }

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("配置列表")
                        .font(.headline)

                    Spacer()

                    Button(action: { showingAddGroup = true }) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(CompactButtonStyle(color: .orange))
                    .help("添加分组")

                    Button(action: onAddProvider) {
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(CompactButtonStyle(color: .blue))
                }

                if providers.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("暂无配置")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(groupedProviders(), id: \.group?.id) { item in
                            GroupSection(
                                group: item.group,
                                providers: item.providers,
                                currentProvider: currentProvider,
                                groups: groups,
                                isCollapsed: collapsedGroups.contains(item.group?.name ?? ""),
                                onToggle: {
                                    let key = item.group?.name ?? ""
                                    if collapsedGroups.contains(key) {
                                        collapsedGroups.remove(key)
                                    } else {
                                        collapsedGroups.insert(key)
                                    }
                                },
                                onEdit: onEdit,
                                onDelete: onDelete,
                                onCopy: onCopy,
                                onSelect: onSelect,
                                onMoveToGroup: onMoveToGroup,
                                onEditGroup: { group in
                                    editingGroup = group
                                },
                                onDeleteGroup: item.group != nil ? { onDeleteGroup(item.group!.name) } : nil
                            )
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddGroup) {
            AddGroupSheet(
                groupName: $newGroupName,
                onAdd: {
                    if !newGroupName.isEmpty {
                        onAddGroup(newGroupName)
                        newGroupName = ""
                    }
                    showingAddGroup = false
                },
                onCancel: {
                    newGroupName = ""
                    showingAddGroup = false
                }
            )
        }
        .sheet(item: $editingGroup) { group in
            EditGroupSheet(group: group, onSave: { updated in
                onUpdateGroup(updated)
                editingGroup = nil
            }, onCancel: {
                editingGroup = nil
            })
        }
    }
}

// MARK: - 分组区块
struct GroupSection: View {
    let group: ProviderGroup?
    let providers: [APIProvider]
    let currentProvider: APIProvider?
    let groups: [String]
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onEdit: (APIProvider) -> Void
    let onDelete: (APIProvider) -> Void
    let onCopy: (APIProvider) -> Void
    let onSelect: (APIProvider) -> Void
    let onMoveToGroup: (APIProvider, String?) -> Void
    let onEditGroup: ((ProviderGroup) -> Void)?
    let onDeleteGroup: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    if let g = group {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(g.name)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("#\(g.priority)")
                            .font(.caption2)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    } else {
                        Image(systemName: "tray")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("未分组")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("(\(providers.count))")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let g = group, let onEditGroup = onEditGroup {
                        Button(action: { onEditGroup(g) }) {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundColor(.blue.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("编辑分组")
                    }

                    if let onDeleteGroup = onDeleteGroup {
                        Button(action: onDeleteGroup) {
                            Image(systemName: "trash")
                                .font(.caption2)
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("删除分组")
                    }
                }
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(spacing: 4) {
                    ForEach(providers) { provider in
                        ProviderRowCompact(
                            provider: provider,
                            isCurrent: provider.id == currentProvider?.id,
                            groups: groups,
                            onEdit: onEdit,
                            onDelete: onDelete,
                            onCopy: onCopy,
                            onSelect: onSelect,
                            onMoveToGroup: onMoveToGroup
                        )
                    }
                }
                .padding(.leading, 18)
            }
        }
    }
}

// MARK: - 添加分组弹窗
struct AddGroupSheet: View {
    @Binding var groupName: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("添加分组")
                .font(.headline)

            TextField("分组名称", text: $groupName)
                .textFieldStyle(ModernTextFieldStyle())

            HStack(spacing: 12) {
                Button("取消", action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())

                Button("添加", action: onAdd)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(groupName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}

// MARK: - 编辑分组弹窗
struct EditGroupSheet: View {
    @State private var name: String
    @State private var priority: Int
    let group: ProviderGroup
    let onSave: (ProviderGroup) -> Void
    let onCancel: () -> Void

    init(group: ProviderGroup, onSave: @escaping (ProviderGroup) -> Void, onCancel: @escaping () -> Void) {
        self.group = group
        self.onSave = onSave
        self.onCancel = onCancel
        self._name = State(initialValue: group.name)
        self._priority = State(initialValue: group.priority)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("编辑分组")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("分组名称")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("分组名称", text: $name)
                    .textFieldStyle(ModernTextFieldStyle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("优先级（数字越小越靠前）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("优先级", value: $priority, format: .number)
                    .textFieldStyle(ModernTextFieldStyle())
            }

            HStack(spacing: 12) {
                Button("取消", action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())

                Button("保存") {
                    var updated = group
                    updated.name = name
                    updated.priority = priority
                    onSave(updated)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

// MARK: - 精简版提供商行
struct ProviderRowCompact: View {
    let provider: APIProvider
    let isCurrent: Bool
    let groups: [String]
    let onEdit: (APIProvider) -> Void
    let onDelete: (APIProvider) -> Void
    let onCopy: (APIProvider) -> Void
    let onSelect: (APIProvider) -> Void
    let onMoveToGroup: (APIProvider, String?) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isCurrent ? Color.green : (provider.isValid ? Color.blue.opacity(0.5) : Color.orange))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.subheadline)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundColor(isCurrent ? .green : .primary)

                    if isCurrent {
                        Text("当前")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(3)
                    }
                }

                Text(provider.url)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                if !isCurrent && provider.isValid {
                    Button(action: { onSelect(provider) }) {
                        Label("选择", systemImage: "checkmark.circle")
                    }
                    Divider()
                }

                Menu("移动到分组") {
                    Button(action: { onMoveToGroup(provider, nil) }) {
                        HStack {
                            Text("未分组")
                            if provider.groupName == nil || provider.groupName?.isEmpty == true {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    if !groups.isEmpty {
                        Divider()
                        ForEach(groups, id: \.self) { group in
                            Button(action: { onMoveToGroup(provider, group) }) {
                                HStack {
                                    Text(group)
                                    if provider.groupName == group {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()
                Button(action: { onEdit(provider) }) {
                    Label("编辑", systemImage: "pencil")
                }
                Button(action: { onCopy(provider) }) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                Divider()
                Button(role: .destructive, action: { onDelete(provider) }) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Color.green.opacity(0.08) : Color(.controlBackgroundColor))
        )
    }
}

// MARK: - 代理设置卡片
struct ProxySettingsCard: View {
    @Binding var proxyHost: String
    @Binding var proxyPort: String
    @Binding var autoStartup: Bool
    let onSave: () -> Void
    let onRefresh: () -> Void
    @ObservedObject private var configManager = ConfigManager.shared
    @State private var launchAgentStatus: Bool = false

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("应用设置")
                    .font(.headline)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开机自动启动")
                            .font(.subheadline)

                        Text("应用将在系统启动时自动运行")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $autoStartup)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                }

                Divider()

                Text("代理设置")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    TextField("服务器地址", text: $proxyHost)
                        .textFieldStyle(ModernTextFieldStyle())

                    TextField("端口", text: $proxyPort)
                        .textFieldStyle(ModernTextFieldStyle())
                        .frame(width: 70)
                }

                HStack(spacing: 8) {
                    Button("保存设置") {
                        onSave()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            launchAgentStatus = configManager.checkLaunchAgentStatus()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("刷新状态") {
                        onRefresh()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .onAppear {
            launchAgentStatus = configManager.checkLaunchAgentStatus()
        }
        .onChange(of: autoStartup) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                launchAgentStatus = configManager.checkLaunchAgentStatus()
            }
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
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
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
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(badgeColor.opacity(0.15))
            )
            .foregroundColor(badgeColor)
    }
}

// MARK: - 自定义按钮样式

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.controlBackgroundColor))
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .foregroundColor(.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
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
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.12))
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
            )
    }
}

// MARK: - 添加和编辑提供商视图

struct AddProviderView: View {
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var key: String = ""
    @State private var largeModel: String = ""
    @State private var smallModel: String = ""
    @State private var selectedGroup: String = ""
    @State private var priority: Int = 0
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configManager = ConfigManager.shared

    let onAdd: (APIProvider) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("添加 API 提供商")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                FormField(label: "名称", placeholder: "输入提供商名称", text: $name)
                FormField(label: "API URL", placeholder: "输入 API 地址", text: $url)
                FormField(label: "API 密钥", placeholder: "输入 API 密钥", text: $key)
                FormField(label: "大模型（可选）", placeholder: "claude-3-opus-20240229", text: $largeModel)
                FormField(label: "小模型（可选）", placeholder: "claude-3-haiku-20240307", text: $smallModel)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("分组（可选）")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: $selectedGroup) {
                            Text("未分组").tag("")
                            ForEach(configManager.groups, id: \.self) { group in
                                Text(group).tag(group)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("优先级")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("0", value: $priority, format: .number)
                            .textFieldStyle(ModernTextFieldStyle())
                            .frame(width: 60)
                    }
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
                        smallModel: smallModel.isEmpty ? nil : smallModel,
                        groupName: selectedGroup.isEmpty ? nil : selectedGroup,
                        priority: priority
                    )
                    onAdd(provider)
                    dismiss()
                }
                .disabled(name.isEmpty || url.isEmpty || key.isEmpty)
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 400, height: 520)
        .background(Color(.windowBackgroundColor))
    }
}

struct EditProviderView: View {
    @State private var name: String
    @State private var url: String
    @State private var key: String
    @State private var largeModel: String
    @State private var smallModel: String
    @State private var selectedGroup: String
    @State private var priority: Int
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configManager = ConfigManager.shared

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
        self._selectedGroup = State(initialValue: provider.groupName ?? "")
        self._priority = State(initialValue: provider.priority)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("编辑 API 提供商")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                FormField(label: "名称", placeholder: "输入提供商名称", text: $name)
                FormField(label: "API URL", placeholder: "输入 API 地址", text: $url)
                FormField(label: "API 密钥", placeholder: "输入 API 密钥", text: $key)
                FormField(label: "大模型（可选）", placeholder: "claude-3-opus-20240229", text: $largeModel)
                FormField(label: "小模型（可选）", placeholder: "claude-3-haiku-20240307", text: $smallModel)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("分组（可选）")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: $selectedGroup) {
                            Text("未分组").tag("")
                            ForEach(configManager.groups, id: \.self) { group in
                                Text(group).tag(group)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("优先级")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("0", value: $priority, format: .number)
                            .textFieldStyle(ModernTextFieldStyle())
                            .frame(width: 60)
                    }
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
                    updatedProvider.groupName = selectedGroup.isEmpty ? nil : selectedGroup
                    updatedProvider.priority = priority
                    onUpdate(updatedProvider)
                    dismiss()
                }
                .disabled(name.isEmpty || url.isEmpty || key.isEmpty)
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 400, height: 520)
        .background(Color(.windowBackgroundColor))
    }
}

struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(ModernTextFieldStyle())
        }
    }
}
