import Foundation

// MARK: - Claude Config Claude 配置

/// Claude Code 配置文件结构
/// Claude Code configuration file structure
struct ClaudeConfig: Codable {
    /// 环境变量配置
    /// Environment variables configuration
    var env: Environment?

    /// 反馈调查状态
    /// Feedback survey state
    var feedbackSurveyState: FeedbackSurveyState?

    // MARK: - Environment

    /// 环境变量
    /// Environment variables
    struct Environment: Codable {
        var ANTHROPIC_API_KEY: String = ""
        var ANTHROPIC_BASE_URL: String = ""
        var ANTHROPIC_MODEL: String?
        var ANTHROPIC_SMALL_FAST_MODEL: String?
        var CLAUDE_CODE_MAX_OUTPUT_TOKENS: String?
        var CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: String?
        var HTTPS_PROXY: String?
        var HTTP_PROXY: String?

        init() {}
    }

    // MARK: - Feedback Survey State

    /// 反馈调查状态
    /// Feedback survey state
    struct FeedbackSurveyState: Codable {
        var lastShownTime: TimeInterval
    }

    init() {
        self.env = Environment()
    }
}