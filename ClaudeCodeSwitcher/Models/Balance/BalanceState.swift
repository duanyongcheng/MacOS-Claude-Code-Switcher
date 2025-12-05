import Foundation
import SwiftUI

// MARK: - Balance State 余额状态

/// 余额查询状态
/// Balance query state
enum BalanceState: Equatable {
    /// 空闲状态，未查询
    /// Idle state, not queried
    case idle

    /// 查询中
    /// Loading
    case loading

    /// 查询成功
    /// Success with balance info
    case success(BalanceInfo)

    /// 查询失败
    /// Failed with error message
    case failure(String)

    /// 是否正在加载
    /// Whether is loading
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// 格式化的金额显示
    /// Formatted amount display
    var formattedAmount: String {
        switch self {
        case .success(let info):
            if info.currency == "tok" {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 0
                let tokenText = formatter.string(from: NSNumber(value: info.amount)) ?? "\(Int(info.amount))"
                return "剩余 \(tokenText) token"
            } else if info.currency == "$" {
                return "$" + String(format: "%.2f", info.amount)
            }
            return "\(info.currency)\(String(format: "%.2f", info.amount))"
        default:
            return "--"
        }
    }

    /// 详细文本
    /// Detail text
    func detailText(for provider: APIProvider?) -> String {
        switch self {
        case .idle:
            return provider == nil ? "选择配置后可查询余额" : "点击刷新余额"
        case .loading:
            return "正在查询余额..."
        case .success(let info):
            var parts: [String] = []
            if info.currency == "$", let tokens = info.tokens {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 0
                let tokenText = formatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
                parts.append("剩余 \(tokenText) token")
            }
            if let updatedAt = info.updatedAt {
                parts.append("更新于 \(DateFormatter.shortTimeFormatter.string(from: updatedAt))")
            }
            return parts.isEmpty ? "已更新" : parts.joined(separator: " · ")
        case .failure(let message):
            return "获取失败：\(message)"
        }
    }

    /// 高亮颜色
    /// Highlight color
    var highlightColor: Color {
        switch self {
        case .success(let info):
            if info.currency == "tok" {
                return .blue
            }
            return info.amount < AppConstants.Token.lowBalanceThreshold ? .orange : .green
        case .failure:
            return .orange
        default:
            return .secondary
        }
    }

    /// 用于菜单显示的标题
    /// Title for menu display
    func menuTitle(for provider: APIProvider?) -> String {
        switch self {
        case .idle:
            return provider == nil ? "余额：未选择配置" : "余额：未查询"
        case .loading:
            return "余额：查询中..."
        case .success(let info):
            let prefix = info.amount < AppConstants.Token.lowBalanceThreshold ? "⚠️ " : ""
            let amountText = "\(info.currency)\(String(format: "%.2f", info.amount))"
            return "\(prefix)余额：\(amountText)"
        case .failure:
            return "⚠️ 余额：--"
        }
    }

    /// 内联显示文本（用于显示在供应商名称旁边）
    /// Inline text for display next to provider name
    func inlineText(for provider: APIProvider?) -> String? {
        guard provider != nil else { return nil }

        switch self {
        case .idle:
            return nil
        case .loading:
            return "查询中..."
        case .success(let info):
            let amountText = "\(info.currency)\(String(format: "%.2f", info.amount))"
            return amountText
        case .failure:
            return "⚠️"
        }
    }

    /// 工具提示文本
    /// Tooltip text
    func tooltip(for provider: APIProvider?) -> String {
        switch self {
        case .idle:
            return provider == nil ? "选择配置后可查询余额" : "点击刷新余额"
        case .loading:
            return "正在查询余额..."
        case .success(let info):
            return info.amount < AppConstants.Token.lowBalanceThreshold ? "余额低于 $\(AppConstants.Token.lowBalanceThreshold)，建议尽快充值\n点击刷新" : "余额状态正常\n点击刷新"
        case .failure(let message):
            return "获取失败：\(message)\n点击重试"
        }
    }

    /// 菜单属性（字体、颜色等）
    /// Menu attributes (font, color, etc.)
    var menuAttributes: [NSAttributedString.Key: Any] {
        var color: NSColor = .secondaryLabelColor
        switch self {
        case .success(let info):
            color = info.amount < AppConstants.Token.lowBalanceThreshold ? .systemOrange : .systemGreen
        case .failure:
            color = .systemOrange
        case .loading:
            color = .secondaryLabelColor
        case .idle:
            color = .secondaryLabelColor
        }

        return [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color
        ]
    }
}

// MARK: - Balance Info 余额信息

/// 余额信息结构
/// Balance information structure
struct BalanceInfo: Equatable {
    /// 余额数量
    /// Balance amount
    let amount: Double

    /// 货币单位（如 "$", "tok"）
    /// Currency unit (e.g., "$", "tok")
    let currency: String

    /// 更新时间
    /// Updated time
    let updatedAt: Date?

    /// 关联的供应商
    /// Associated provider
    let provider: APIProvider

    /// Token 数量（可选）
    /// Token count (optional)
    let tokens: Int?

    init(amount: Double, currency: String, updatedAt: Date? = nil, provider: APIProvider, tokens: Int? = nil) {
        self.amount = amount
        self.currency = currency
        self.updatedAt = updatedAt
        self.provider = provider
        self.tokens = tokens
    }
}

