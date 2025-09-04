import Foundation

struct ClaudeConfig: Codable {
    var env: Environment?
    var feedbackSurveyState: FeedbackSurveyState?
    
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
    
    struct FeedbackSurveyState: Codable {
        var lastShownTime: TimeInterval
    }
    
    init() {
        self.env = Environment()
    }
}