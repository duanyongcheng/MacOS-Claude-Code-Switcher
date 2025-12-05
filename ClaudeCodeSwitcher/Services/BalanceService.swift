import Foundation
import OSLog

// MARK: - Balance Result 余额结果

/// 余额查询结果
/// Balance query result
struct BalanceResult {
    /// 可用 Token 数量
    /// Available tokens count
    let availableTokens: Int

    /// 总授予 Token 数量
    /// Total granted tokens
    let totalGranted: Int?

    /// 已使用 Token 数量
    /// Total used tokens
    let totalUsed: Int?
}

// MARK: - URLSessionTaskDelegate

extension BalanceService: URLSessionTaskDelegate {
    /// 处理 HTTP 重定向，保留 Authorization 头
    /// Handle HTTP redirects while preserving Authorization header
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var newRequest = request

        // 保留原始 Authorization 头，避免重定向后被移除导致 401
        // Preserve original Authorization header to avoid 401 after redirect
        if let auth = task.originalRequest?.value(forHTTPHeaderField: "Authorization") {
            newRequest.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        completionHandler(newRequest)
    }
}

// MARK: - Balance Service Error 余额服务错误

/// 余额服务错误类型
/// Balance service error types
enum BalanceServiceError: LocalizedError {
    /// 无效的 URL
    /// Invalid URL
    case invalidURL(String?)

    /// API 密钥缺失
    /// Missing API key
    case missingAPIKey

    /// 传输错误
    /// Transport error
    case transport(Error)

    /// HTTP 错误状态码
    /// Bad HTTP status code
    case badStatus(Int, String?, String?)

    /// 解码失败
    /// Decoding failure
    case decoding(String?)

    /// 空数据
    /// Empty data
    case emptyData

    /// 错误描述信息
    /// Error description message
    var errorDescription: String? {
        switch self {
        case .invalidURL(let raw):
            if let raw, !raw.isEmpty {
                return "无效的链接: \(raw)，请确认包含 http/https 并可访问 /api/usage/token"
            }
            return "无效的链接"
        case .transport(let error):
            return error.localizedDescription
        case .missingAPIKey:
            return "API 密钥为空，请在配置中填写"
        case .badStatus(let code, let message, let body):
            if let message, !message.isEmpty {
                return "服务器返回 \(code)：\(message)"
            } else if let body, !body.isEmpty {
                return "服务器返回 \(code)：\(body.prefix(120))"
            } else {
                return "服务器返回错误码 \(code)"
            }
        case .decoding(let detail):
            return detail ?? "解析响应失败"
        case .emptyData:
            return "响应为空"
        }
    }
}

// MARK: - Balance Service 余额服务

/// 余额查询服务
/// Service for querying API provider balance
final class BalanceService: NSObject {
    // MARK: - Properties

    /// 日志记录器
    /// Logger instance
    private let logger = Logger(subsystem: "ClaudeCodeSwitcher", category: "BalanceService")

    /// URL 会话
    /// URL session with custom configuration
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - Private Models

    /// Token 使用量响应数据
    /// Token usage response data
    private struct TokenUsageResponse: Codable {
        let code: Bool?
        let message: String?
        let data: TokenUsageData?
    }

    /// Token 使用量详细数据
    /// Token usage detailed data
    private struct TokenUsageData: Codable {
        let totalGranted: Int?
        let totalUsed: Int?
        let totalAvailable: Int?
        
        enum CodingKeys: String, CodingKey {
            case totalGranted = "total_granted"
            case totalUsed = "total_used"
            case totalAvailable = "total_available"
        }
    }

    // MARK: - Public Methods

    /// 查询提供商余额
    /// Fetch balance for provider
    /// - Parameters:
    ///   - provider: API 提供商 / API provider
    ///   - completion: 完成回调 / Completion callback
    func fetchBalance(for provider: APIProvider, completion: @escaping (Result<BalanceResult, BalanceServiceError>) -> Void) {
        let builtURL = buildBalanceURL(from: provider.url)
        guard let url = builtURL else {
            print("BalanceService buildBalanceURL 失败，原始地址: \(provider.url)")
            completion(.failure(.invalidURL(provider.url)))
            return
        }
        
        let apiKey = provider.key
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression) // 去除所有空白
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            completion(.failure(.missingAPIKey))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let maskedKey: String = {
            let clean = apiKey.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            if clean.count <= 8 { return String(repeating: "*", count: clean.count) }
            let prefix = clean.prefix(4)
            let suffix = clean.suffix(3)
            return "\(prefix)***\(suffix)"
        }()
        logger.info("BalanceService 请求地址: \(url.absoluteString, privacy: .public), Header Authorization: Bearer \(maskedKey, privacy: .public)")
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error = error {
                completion(.failure(.transport(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidURL(url.absoluteString)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.emptyData))
                return
            }
            
            let rawBody = String(data: data, encoding: .utf8)
            
            // 优先解析出 message，辅助错误提示
            let decoded = try? JSONDecoder().decode(TokenUsageResponse.self, from: data)
            let serverMessage = decoded?.message
            self.logger.info("BalanceService response status: \(httpResponse.statusCode), body: \(rawBody ?? "<no body>", privacy: .public)")
            
            guard 200..<300 ~= httpResponse.statusCode else {
                completion(.failure(.badStatus(httpResponse.statusCode, serverMessage, rawBody)))
                return
            }
            
            if let tokenData = decoded,
               decoded?.code != false, // code==false 视为业务失败
               let usage = tokenData.data,
               let available = usage.totalAvailable {
                let result = BalanceResult(
                    availableTokens: available,
                    totalGranted: usage.totalGranted,
                    totalUsed: usage.totalUsed
                )
                completion(.success(result))
            } else {
                let message = serverMessage ?? rawBody
                completion(.failure(.decoding(message)))
            }
        }
        
        task.resume()
    }

    // MARK: - Private Methods

    /// 构建余额查询 URL
    /// Build balance query URL from base URL
    /// - Parameter base: 基础 URL / Base URL
    /// - Returns: 完整的余额查询 URL / Complete balance query URL
    private func buildBalanceURL(from base: String) -> URL? {
        // 清理常见的空白字符（包含中文空格）
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{00a0}\u{3000}"))
        let trimmed = base
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: trimSet)
            .replacingOccurrences(of: "：//", with: "://") // 兼容全角冒号
        guard !trimmed.isEmpty else { return nil }
        
        // 确保有 schema，默认 https
        let baseWithScheme: String = {
            let lower = trimmed.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
                return trimmed
            }
            return "https://" + trimmed
        }()
        
        let needsPath = !baseWithScheme.contains("/api/usage/token")
        var candidates: [URL] = []
        
        // 优先使用 URLComponents 避免重复斜杠
        if var components = URLComponents(string: baseWithScheme) {
            if needsPath {
                let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                components.path = path.isEmpty ? "/api/usage/token" : "/\(path)/api/usage/token"
            }
            if let url = components.url {
                candidates.append(url)
            }
        }
        
        // 退化方案，直接字符串拼接并尝试编码
        if needsPath {
            let appended = baseWithScheme.hasSuffix("/") ? baseWithScheme + "api/usage/token" : baseWithScheme + "/api/usage/token"
            if let url = URL(string: appended) {
                candidates.append(url)
            } else if
                let encoded = appended.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
                let url = URL(string: encoded) {
                candidates.append(url)
            }
        } else if let url = URL(string: baseWithScheme) {
            candidates.append(url)
        }
        
        return candidates.first
    }
}
