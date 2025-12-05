import Foundation
import Network
import Combine

// MARK: - Local Proxy Service 本地代理服务

/// 本地 HTTP 代理服务
/// Provides local HTTP proxy with automatic failover across multiple providers
class LocalProxyService: ObservableObject {
    // MARK: - Singleton

    static let shared = LocalProxyService()

    // MARK: - Properties

    /// 网络监听器
    /// Network listener
    private var listener: NWListener?

    /// 是否正在运行
    /// Whether service is running
    private var isRunning = false

    /// 调度队列
    /// Dispatch queue for proxy operations
    private let queue = DispatchQueue(label: "com.ccs.proxy", qos: .userInitiated)

    /// URL 会话
    /// URL session for forwarding requests
    private let session: URLSession

    // MARK: - Provider Health Tracking 提供商健康追踪

    /// 惩罚值锁（线程安全）
    /// Penalty lock for thread safety
    private let penaltyLock = NSLock()

    /// 提供商惩罚值映射表
    /// Provider penalty map
    private var providerPenalties: [UUID: Int] = [:]

    /// 当前正在请求的服务商
    /// Currently requesting provider
    @Published var currentRequestingProvider: APIProvider?

    /// 最后一次成功请求的服务商
    /// Last successful provider
    @Published var lastSuccessProvider: APIProvider?

    /// 最后一次成功请求的时间
    /// Last success time
    @Published var lastSuccessTime: Date?

    /// 是否正在请求中
    /// Whether currently requesting
    @Published var isRequesting: Bool = false

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
        observeConfigChanges()
    }

    // MARK: - Health Management 健康管理

    /// 更新提供商的惩罚值
    /// Update provider penalty value
    /// - Parameters:
    ///   - providerId: 提供商 ID / Provider ID
    ///   - success: 请求是否成功 / Whether request succeeded
    private func updatePenalty(for providerId: UUID, success: Bool) {
        penaltyLock.lock()
        defer { penaltyLock.unlock() }

        let current = providerPenalties[providerId] ?? 0
        if success {
            // 成功：缓慢恢复优先级
            // Success: slow recovery
            if current > 0 {
                providerPenalties[providerId] = max(0, current - AppConstants.ProxyPool.penaltyRecovery)
            }
        } else {
            // 失败：快速降低优先级
            // Failure: fast degradation
            providerPenalties[providerId] = current + AppConstants.ProxyPool.penaltyIncrease
            print("[Proxy] Increased penalty for provider \(providerId), new penalty: \(providerPenalties[providerId]!)")
        }
    }

    /// 按健康度排序提供商
    /// Sort providers by health (priority - penalty)
    /// - Parameter providers: 提供商列表 / Provider list
    /// - Returns: 排序后的提供商列表 / Sorted provider list
    private func getSortedProviders(_ providers: [APIProvider]) -> [APIProvider] {
        penaltyLock.lock()
        let penalties = providerPenalties
        penaltyLock.unlock()

        return providers.sorted { p1, p2 in
            let penalty1 = penalties[p1.id] ?? 0
            let penalty2 = penalties[p2.id] ?? 0

            let score1 = p1.priority - penalty1
            let score2 = p2.priority - penalty2

            // 如果分数相同，保持原有相对顺序（依靠 priority）
            if score1 == score2 {
                return p1.priority > p2.priority
            }
            return score1 > score2
        }
    }

    /// 获取代理服务器端口
    /// Get proxy server port
    var port: Int {
        ConfigManager.shared.proxyModePort
    }

    // MARK: - Public Methods - Server Control 服务器控制

    /// 启动代理服务器
    /// Start proxy server
    func start() {
        guard !isRunning else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("[Proxy] Server started on port \(self?.port ?? 0)")
                    self?.isRunning = true
                case .failed(let error):
                    print("[Proxy] Server failed: \(error)")
                    self?.isRunning = false
                case .cancelled:
                    print("[Proxy] Server stopped")
                    self?.isRunning = false
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)
        } catch {
            print("[Proxy] Failed to start: \(error)")
        }
    }

    /// 停止代理服务器
    /// Stop proxy server
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        print("[Proxy] Server stopped")
    }

    /// 重启代理服务器
    /// Restart proxy server
    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }

    // MARK: - Private Methods - Observers 观察者

    /// 监听配置变更
    /// Observe configuration changes
    private func observeConfigChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(proxyModeChanged(_:)),
            name: .proxyModeDidChange,
            object: nil
        )
    }

    /// 处理代理模式变更通知
    /// Handle proxy mode change notification
    @objc private func proxyModeChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }
        if enabled {
            start()
        } else {
            stop()
        }
    }

    // MARK: - Private Methods - Connection Handling 连接处理

    /// 处理新连接
    /// Handle new connection
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveFullRequest(connection: connection, buffer: Data())
    }

    /// 接收完整的 HTTP 请求
    /// Receive full HTTP request
    /// - Parameters:
    ///   - connection: 网络连接 / Network connection
    ///   - buffer: 数据缓冲区 / Data buffer
    private func receiveFullRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            if let error = error {
                print("[Proxy] Receive error: \(error)")
                connection.cancel()
                return
            }

            var newBuffer = buffer
            if let data = data {
                newBuffer.append(data)
            }

            if let (headers, headerEndIndex) = self.parseHTTPHeaders(newBuffer) {
                let contentLength = self.getContentLength(from: headers)

                let bodyStartIndex = headerEndIndex
                let currentBodyLength = newBuffer.count - bodyStartIndex

                if currentBodyLength >= contentLength {
                    self.processRequest(data: newBuffer, connection: connection)
                } else {
                    self.receiveFullRequest(connection: connection, buffer: newBuffer)
                }
            } else if newBuffer.count > 1024 * 1024 {
                print("[Proxy] Request too large without complete headers")
                self.sendErrorResponse(connection: connection, statusCode: 413, message: "Request too large")
            } else {
                self.receiveFullRequest(connection: connection, buffer: newBuffer)
            }
        }
    }

    // MARK: - Private Methods - HTTP Parsing HTTP 解析

    /// 解析 HTTP 请求头
    /// Parse HTTP headers
    /// - Parameter data: 原始数据 / Raw data
    /// - Returns: 请求头字典和头部结束位置 / Headers dictionary and header end index
    private func parseHTTPHeaders(_ data: Data) -> (headers: [String: String], headerEndIndex: Int)? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }

        guard let range = str.range(of: "\r\n\r\n") else { return nil }

        let headerPart = String(str[..<range.lowerBound])
        let headerEndIndex = str.distance(from: str.startIndex, to: range.upperBound)

        var headers: [String: String] = [:]
        let lines = headerPart.components(separatedBy: "\r\n")

        for line in lines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key.lowercased()] = value
            }
        }

        return (headers, headerEndIndex)
    }

    /// 获取 Content-Length
    /// Get Content-Length from headers
    private func getContentLength(from headers: [String: String]) -> Int {
        if let lengthStr = headers["content-length"], let length = Int(lengthStr) {
            return length
        }
        return 0
    }

    /// 处理请求
    /// Process incoming request
    private func processRequest(data: Data, connection: NWConnection) {
        let providers = ConfigManager.shared.getProxyPoolProviders()
        guard !providers.isEmpty else {
            sendErrorResponse(connection: connection, statusCode: 503, message: "No providers configured in proxy pool")
            return
        }

        forwardRequestWithFailover(
            requestData: data,
            providers: providers,
            startIndex: 0,
            connection: connection
        )
    }

    /// 获取提供商的惩罚值
    /// Get penalty value for provider
    /// - Parameter providerId: 提供商 ID / Provider ID
    /// - Returns: 惩罚值 / Penalty value
    func getPenalty(for providerId: UUID) -> Int {
        penaltyLock.lock()
        defer { penaltyLock.unlock() }
        return providerPenalties[providerId] ?? 0
    }

    // MARK: - Private Methods - Request Forwarding 请求转发

    /// 带故障转移的请求转发
    /// Forward request with automatic failover
    /// - Parameters:
    ///   - requestData: 原始请求数据 / Original request data
    ///   - providers: 提供商列表 / Provider list
    ///   - startIndex: 起始索引 / Start index
    ///   - connection: 客户端连接 / Client connection
    private func forwardRequestWithFailover(
        requestData: Data,
        providers: [APIProvider],
        startIndex: Int,
        connection: NWConnection
    ) {
        guard startIndex < providers.count else {
            DispatchQueue.main.async {
                self.currentRequestingProvider = nil
                self.isRequesting = false
            }
            sendErrorResponse(connection: connection, statusCode: 502, message: "All providers failed")
            return
        }

        let provider = providers[startIndex]
        print("[Proxy] Trying provider: \(provider.name) (\(startIndex + 1)/\(providers.count))")

        // 更新当前正在请求的服务商
        DispatchQueue.main.async {
            self.currentRequestingProvider = provider
            self.isRequesting = true
        }

        forwardRequest(requestData: requestData, to: provider) { [weak self] result in
            switch result {
            case .success(let responseData):
                // 请求成功，减少惩罚
                self?.updatePenalty(for: provider.id, success: true)

                self?.sendResponse(connection: connection, data: responseData)
                // 请求成功后更新状态
                DispatchQueue.main.async {
                    self?.lastSuccessProvider = provider
                    self?.lastSuccessTime = Date()
                    self?.currentRequestingProvider = nil
                    self?.isRequesting = false
                }
            case .failure(let error):
                print("[Proxy] Provider \(provider.name) failed: \(error.localizedDescription)")

                // 请求失败，增加惩罚
                self?.updatePenalty(for: provider.id, success: false)

                self?.forwardRequestWithFailover(
                    requestData: requestData,
                    providers: providers,
                    startIndex: startIndex + 1,
                    connection: connection
                )
            }
        }
    }

    /// 转发单个请求到提供商
    /// Forward single request to provider
    /// - Parameters:
    ///   - requestData: 请求数据 / Request data
    ///   - provider: 目标提供商 / Target provider
    ///   - completion: 完成回调 / Completion callback
    private func forwardRequest(
        requestData: Data,
        to provider: APIProvider,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard let parsed = parseHTTPRequest(requestData) else {
            completion(.failure(ProxyError.invalidRequest))
            return
        }

        let (method, path, headers, body) = parsed

        guard let providerURL = URL(string: provider.url) else {
            completion(.failure(ProxyError.invalidProviderURL))
            return
        }

        let targetURL = buildTargetURL(basePath: path, providerURL: providerURL)
        guard let finalURL = targetURL else {
            completion(.failure(ProxyError.invalidProviderURL))
            return
        }

        let timeout = TimeInterval(ConfigManager.shared.proxyRequestTimeout)
        print("[Proxy] Forwarding to: \(finalURL.absoluteString) (timeout: \(Int(timeout))s)")

        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        request.timeoutInterval = timeout

        for (key, value) in headers {
            let lowerKey = key.lowercased()
            if lowerKey == "host" {
                request.setValue(providerURL.host, forHTTPHeaderField: key)
            } else if lowerKey == "content-length" || lowerKey == "transfer-encoding" {
                continue
            } else if lowerKey == "authorization" || lowerKey == "x-api-key" {
                continue
            } else {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        request.setValue("Bearer \(provider.key)", forHTTPHeaderField: "Authorization")
        request.setValue(provider.key, forHTTPHeaderField: "x-api-key")

        if let body = body, !body.isEmpty {
            request.httpBody = body
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(ProxyError.invalidResponse))
                return
            }

            // 触发 failover 的状态码：
            // - 401: 未授权（API Key 无效）
            // - 403: 禁止访问（余额不足、权限不足等）
            // - 429: 限流
            // - 5xx: 服务器错误
            let failoverStatusCodes: Set<Int> = [401, 403, 429]
            if httpResponse.statusCode >= 500 || failoverStatusCodes.contains(httpResponse.statusCode) {
                print("[Proxy] Provider returned \(httpResponse.statusCode), will try next")
                completion(.failure(ProxyError.serverError(httpResponse.statusCode)))
                return
            }

            let responseData = self?.buildHTTPResponse(
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields,
                body: data
            ) ?? Data()

            completion(.success(responseData))
        }
        task.resume()
    }

    /// 构建目标 URL
    /// Build target URL from base path and provider URL
    /// - Parameters:
    ///   - basePath: 基础路径 / Base path
    ///   - providerURL: 提供商 URL / Provider URL
    /// - Returns: 完整的目标 URL / Complete target URL
    private func buildTargetURL(basePath: String, providerURL: URL) -> URL? {
        var path = basePath

        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            if let fullURL = URL(string: path) {
                path = fullURL.path
                if let query = fullURL.query {
                    path += "?\(query)"
                }
            }
        }

        if !path.hasPrefix("/") {
            path = "/" + path
        }

        var baseURLString = providerURL.absoluteString
        if baseURLString.hasSuffix("/") {
            baseURLString = String(baseURLString.dropLast())
        }

        let fullURLString = baseURLString + path
        return URL(string: fullURLString)
    }

    /// 解析 HTTP 请求
    /// Parse HTTP request
    /// - Parameter data: 请求数据 / Request data
    /// - Returns: 请求方法、路径、头部和正文 / Method, path, headers and body
    private func parseHTTPRequest(_ data: Data) -> (method: String, path: String, headers: [String: String], body: Data?)? {
        // 查找 header 结束标记的字节位置
        let headerEndMarker = Data("\r\n\r\n".utf8)
        guard let headerEndByteIndex = data.range(of: headerEndMarker)?.upperBound else {
            return nil
        }

        let headerData = data.subdata(in: 0..<(headerEndByteIndex - 4))
        guard let headerStr = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerStr.components(separatedBy: "\r\n")

        guard let firstLine = lines.first else { return nil }

        let parts = firstLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        var body: Data?
        if headerEndByteIndex < data.count {
            body = data.subdata(in: headerEndByteIndex..<data.count)
        }

        print("[Proxy] Parsed request: \(method) \(path), body size: \(body?.count ?? 0) bytes")

        return (method, path, headers, body)
    }

    /// 构建 HTTP 响应
    /// Build HTTP response
    /// - Parameters:
    ///   - statusCode: HTTP 状态码 / HTTP status code
    ///   - headers: 响应头 / Response headers
    ///   - body: 响应正文 / Response body
    /// - Returns: 完整的 HTTP 响应数据 / Complete HTTP response data
    private func buildHTTPResponse(statusCode: Int, headers: [AnyHashable: Any], body: Data?) -> Data {
        let statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"

        var filteredHeaders: [String: String] = [:]
        for (key, value) in headers {
            guard let keyStr = key as? String, let valueStr = value as? String else { continue }
            let lowerKey = keyStr.lowercased()
            if lowerKey == "transfer-encoding" || lowerKey == "content-encoding" {
                continue
            }
            filteredHeaders[keyStr] = valueStr
        }

        if let body = body {
            filteredHeaders["Content-Length"] = "\(body.count)"
        }

        for (key, value) in filteredHeaders {
            response += "\(key): \(value)\r\n"
        }

        response += "\r\n"

        var responseData = response.data(using: .utf8) ?? Data()
        if let body = body {
            responseData.append(body)
        }

        return responseData
    }

    /// 发送响应到客户端
    /// Send response to client
    /// - Parameters:
    ///   - connection: 客户端连接 / Client connection
    ///   - data: 响应数据 / Response data
    private func sendResponse(connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[Proxy] Send error: \(error)")
            }
            connection.cancel()
        })
    }

    /// 发送错误响应
    /// Send error response to client
    /// - Parameters:
    ///   - connection: 客户端连接 / Client connection
    ///   - statusCode: HTTP 状态码 / HTTP status code
    ///   - message: 错误消息 / Error message
    private func sendErrorResponse(connection: NWConnection, statusCode: Int, message: String) {
        let body = "{\"error\": {\"message\": \"\(message)\", \"type\": \"proxy_error\"}}"
        let response = buildHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: body.data(using: .utf8)
        )
        sendResponse(connection: connection, data: response)
    }
}

// MARK: - Proxy Error 代理错误

/// 代理服务错误类型
/// Proxy service error types
enum ProxyError: LocalizedError {
    /// 无效的 HTTP 请求
    /// Invalid HTTP request
    case invalidRequest

    /// 无效的提供商 URL
    /// Invalid provider URL
    case invalidProviderURL

    /// 无效的响应
    /// Invalid response
    case invalidResponse

    /// 服务器错误
    /// Server error with status code
    case serverError(Int)

    /// 所有提供商都失败
    /// All providers failed
    case allProvidersFailed

    /// 错误描述
    /// Error description
    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid HTTP request"
        case .invalidProviderURL:
            return "Invalid provider URL"
        case .invalidResponse:
            return "Invalid response from provider"
        case .serverError(let code):
            return "Server error: \(code)"
        case .allProvidersFailed:
            return "All providers failed"
        }
    }
}
