import Foundation
import Network
import Combine

class LocalProxyService: ObservableObject {
    static let shared = LocalProxyService()

    private var listener: NWListener?
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.ccs.proxy", qos: .userInitiated)
    private let session: URLSession

    /// 当前正在请求的服务商
    @Published var currentRequestingProvider: APIProvider?
    /// 最后一次成功请求的服务商
    @Published var lastSuccessProvider: APIProvider?
    /// 最后一次成功请求的时间
    @Published var lastSuccessTime: Date?
    /// 是否正在请求中
    @Published var isRequesting: Bool = false

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
        observeConfigChanges()
    }

    var port: Int {
        ConfigManager.shared.proxyModePort
    }

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

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        print("[Proxy] Server stopped")
    }

    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }

    private func observeConfigChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(proxyModeChanged(_:)),
            name: .proxyModeDidChange,
            object: nil
        )
    }

    @objc private func proxyModeChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveFullRequest(connection: connection, buffer: Data())
    }

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

    private func getContentLength(from headers: [String: String]) -> Int {
        if let lengthStr = headers["content-length"], let length = Int(lengthStr) {
            return length
        }
        return 0
    }

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
                self?.forwardRequestWithFailover(
                    requestData: requestData,
                    providers: providers,
                    startIndex: startIndex + 1,
                    connection: connection
                )
            }
        }
    }

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

    private func sendResponse(connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[Proxy] Send error: \(error)")
            }
            connection.cancel()
        })
    }

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

enum ProxyError: LocalizedError {
    case invalidRequest
    case invalidProviderURL
    case invalidResponse
    case serverError(Int)
    case allProvidersFailed

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
