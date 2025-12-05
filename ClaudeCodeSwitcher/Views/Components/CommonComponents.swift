import SwiftUI

// MARK: - Card View 卡片视图

/// 通用卡片容器
/// Common card container
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

// MARK: - Status Badge 状态徽章

/// 状态徽章组件
/// Status badge component
struct StatusBadge: View {
    let status: String

    /// 根据状态文本返回对应的颜色
    /// Returns color based on status text
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

// MARK: - Text Field Style 文本框样式

/// 现代化文本框样式
/// Modern text field style
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

// MARK: - Form Field 表单字段

/// 通用表单字段组件
/// Common form field component
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

// MARK: - Mini Stats Card 迷你统计卡片

/// 迷你统计数据卡片
/// Mini statistics card
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

// MARK: - Day Stats Mini 每日统计迷你卡片

/// 每日统计迷你卡片
/// Daily statistics mini card
struct DayStatsMini: View {
    let dayStats: DailyStatsData

    /// 日期标签（今天、昨天、前天）
    /// Date label (today, yesterday, day before yesterday)
    private var dayLabel: String {
        if Calendar.current.isDateInToday(dayStats.date) {
            return "今天"
        } else if Calendar.current.isDateInYesterday(dayStats.date) {
            return "昨天"
        } else {
            return "前天"
        }
    }

    /// 是否为今天
    /// Whether is today
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
