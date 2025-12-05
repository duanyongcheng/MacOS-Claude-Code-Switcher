import Foundation

/// 应用程序全局常量定义
/// Application-wide constants definition
struct AppConstants {

    // MARK: - Proxy Pool 代理池配置

    /// 代理池相关常量
    /// Proxy pool related constants
    struct ProxyPool {
        /// 代理池分组名称
        /// Proxy pool group name
        static let name = "🔀 代理池"

        /// 代理池分组固定 UUID
        /// Fixed UUID for proxy pool group
        static let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        /// 默认代理服务器端口
        /// Default proxy server port
        static let defaultPort = 32000

        /// 默认请求超时时间（秒）
        /// Default request timeout (seconds)
        static let defaultTimeout = 120

        /// 最小超时时间（秒）
        /// Minimum timeout (seconds)
        static let minTimeout = 10

        /// 最大超时时间（秒）
        /// Maximum timeout (seconds)
        static let maxTimeout = 600

        /// 成功时惩罚值恢复量
        /// Penalty recovery on success
        static let penaltyRecovery = 1

        /// 失败时惩罚值增加量
        /// Penalty increase on failure
        static let penaltyIncrease = 10
    }

    // MARK: - Token Conversion Token 转换

    /// Token 相关常量
    /// Token related constants
    struct Token {
        /// 每美元对应的 token 数量
        /// Tokens per dollar
        static let tokensPerDollar = 500_000.0

        /// 低余额警告阈值（美元）
        /// Low balance warning threshold (dollars)
        static let lowBalanceThreshold = 5.0
    }

    // MARK: - UI Configuration UI 配置

    /// UI 相关常量
    /// UI related constants
    struct UI {
        /// 状态栏图标宽度
        /// Status bar icon width
        static let statusBarIconWidth: CGFloat = 20

        /// 状态栏图标尺寸
        /// Status bar icon size
        static let statusBarIconSize = NSSize(width: 30, height: 30)

        /// 设置窗口默认尺寸
        /// Settings window default size
        static let settingsWindowSize = NSSize(width: 520, height: 680)

        /// 设置窗口最小尺寸
        /// Settings window minimum size
        static let settingsWindowMinSize = NSSize(width: 480, height: 600)
    }

    // MARK: - File Paths 文件路径

    /// 文件路径相关常量
    /// File path related constants
    struct Paths {
        /// Claude 配置目录名
        /// Claude config directory name
        static let claudeDir = ".claude"

        /// Claude 配置文件名
        /// Claude config file name
        static let claudeConfigFile = "settings.json"

        /// 应用配置目录名
        /// App config directory name
        static let appConfigDir = ".config/ccs"

        /// 应用配置文件名
        /// App config file name
        static let appConfigFile = "claude-switch.json"

        /// Claude 项目目录名
        /// Claude projects directory name
        static let claudeProjectsDir = "projects"

        /// 配置文件权限
        /// Config file permissions
        static let configFilePermissions: UInt16 = 0o600
    }

    // MARK: - API Configuration API 配置

    /// API 相关常量
    /// API related constants
    struct API {
        /// 余额查询 API 路径
        /// Balance query API path
        static let balanceEndpoint = "/api/usage/token"

        /// 代理模式默认 API Key 标识
        /// Proxy mode default API key identifier
        static let proxyModeKey = "ccs-proxy-mode"

        /// 请求超时时间（秒）
        /// Request timeout (seconds)
        static let requestTimeout: TimeInterval = 15

        /// 资源超时时间（秒）
        /// Resource timeout (seconds)
        static let resourceTimeout: TimeInterval = 30

        /// 触发 failover 的状态码
        /// Status codes that trigger failover
        static let failoverStatusCodes: Set<Int> = [401, 403, 429]
    }

    // MARK: - Notification Names 通知名称

    /// 通知名称常量
    /// Notification name constants
    struct Notifications {
        static let configDidChange = "configDidChange"
        static let balanceDidUpdate = "balanceDidUpdate"
        static let proxyModeDidChange = "proxyModeDidChange"
    }

    // MARK: - UserDefaults Keys UserDefaults 键

    /// UserDefaults 键常量
    /// UserDefaults key constants
    struct UserDefaultsKeys {
        static let collapsedGroups = "collapsedGroups"
    }
}
