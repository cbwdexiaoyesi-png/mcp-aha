import Foundation
import Network

@MainActor
class MCPServerManager: ObservableObject {
    static let shared = MCPServerManager()

    @Published var isRunning = false
    @Published var logs: [String] = []
    @Published var connectedClients: Int = 0

    private var server: MCPServer?
    private var listener: NWListener?

    private init() {}

    func start(mcpConfig: MCPConfig) throws {
        let port = NWEndpoint.Port(rawValue: UInt16(mcpConfig.port))!

        listener = try NWListener(using: .tcp, on: port)

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.addLog("服务器监听端口: \(mcpConfig.port)")
                case .failed(let error):
                    self?.addLog("监听失败: \(error)")
                    self?.isRunning = false
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))

        let serverInstance = MCPServer(
            endpoints: EndpointStore.shared.endpoints,
            serverProfiles: ServerProfileStore.shared.profiles
        )
        serverInstance.logger = { [weak self] message in
            Task { @MainActor in self?.addLog(message) }
        }
        server = serverInstance
    }

    func stop() {
        listener?.cancel()
        listener = nil
        server = nil
        isRunning = false
        connectedClients = 0
        addLog("服务已停止")
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { @MainActor in
                    self?.processRequest(data: data, connection: connection)
                }
            }

            if !isComplete && error == nil {
                // 继续接收数据（用于长连接）
            } else {
                connection.cancel()
            }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            connection.cancel()
            return
        }

        // 解析 HTTP 首行和 MCP JSON，拼出可读日志
        let httpLine = request.components(separatedBy: "\r\n").first ?? ""
        var logLine  = "收到请求: \(httpLine)"
        if let jsonStart = request.firstIndex(of: "{"),
           let body = try? JSONSerialization.jsonObject(with: Data(request[jsonStart...].utf8)) as? [String: Any],
           let method = body["method"] as? String {
            if method == "tools/call",
               let name = (body["params"] as? [String: Any])?["name"] as? String {
                logLine = "调用工具: \(name)"
            } else {
                logLine = "MCP \(method)"
            }
        }
        addLog(logLine)

        guard let response = server?.handle(request: request) else {
            connection.cancel()
            return
        }

        let responseData = Data(response.utf8)
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func addLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        logs.append("[\(timestamp)] \(message)")
    }
}

class MCPServer {
    let endpoints: [APIEndpoint]
    let serverProfiles: [ServerProfile]   // snapshot at server start time
    private let jsEngine = JSEngine()

    /// 日志回调，由 MCPServerManager 注入
    var logger: ((String) -> Void)?

    init(endpoints: [APIEndpoint], serverProfiles: [ServerProfile]) {
        self.endpoints      = endpoints.filter { $0.isEnabled }
        self.serverProfiles = serverProfiles
    }

    private func log(_ message: String) {
        logger?(message)
    }

    func handle(request: String) -> String? {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        let httpMethod = parts[0]
        let rawPath    = parts[1].components(separatedBy: "?")[0] // strip query string

        guard httpMethod == "POST" else {
            return httpResponse(status: 404, body: "{\"error\":\"Not Found\"}")
        }

        // 路由：根据路径决定暴露哪些 endpoints
        if let scopedEndpoints = resolveEndpoints(for: rawPath) {
            if let body = handleMCPRequest(request: request, endpoints: scopedEndpoints) {
                return httpResponse(status: 200, body: body)
            }
            return httpResponse(status: 400, body: "{\"error\":\"Bad Request\"}")
        }

        return httpResponse(status: 404, body: "{\"error\":\"Not Found\"}")
    }

    /// 根据请求路径返回对应的 endpoints；路径不匹配时返回 nil
    private func resolveEndpoints(for path: String) -> [APIEndpoint]? {
        // 全量入口
        if path == "/mcp" || path == "/mcp/" { return endpoints }
        // 按服务器配置路由
        for profile in serverProfiles {
            if path == profile.mcpPath || path == profile.mcpPath + "/" {
                return endpoints.filter { $0.serverID == profile.id }
            }
        }
        return nil
    }

    private func handleMCPRequest(request: String, endpoints eps: [APIEndpoint]) -> String? {
        guard let jsonStart = request.firstIndex(of: "{"),
              let jsonData = String(request[jsonStart...]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let method = json["method"] as? String else {
            return toJSON(["jsonrpc": "2.0", "id": NSNull(),
                           "error": ["code": -32700, "message": "Parse error"]])
        }

        let requestId = json["id"]

        switch method {
        case "initialize":
            return initializeResponse(id: requestId)
        case "tools/list":
            return toolsListResponse(endpoints: eps, id: requestId)
        case "tools/call":
            return toolsCallResponse(endpoints: eps, params: json["params"] as? [String: Any], id: requestId)
        case "resources/list":
            return resourcesListResponse(endpoints: eps, id: requestId)
        case "resources/read":
            return resourcesReadResponse(endpoints: eps, params: json["params"] as? [String: Any], id: requestId)
        case "prompts/list":
            return promptsListResponse(id: requestId)
        case "prompts/get":
            return promptsGetResponse(params: json["params"] as? [String: Any], id: requestId)
        case "logging/setLevel":
            return loggingSetLevelResponse(params: json["params"] as? [String: Any], id: requestId)
        case "ping":
            return pingResponse(id: requestId)
        default:
            return errorResponse(code: -32601, message: "Method not found", id: requestId)
        }
    }

    private func initializeResponse(id: Any?) -> String? {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [:],
                    "resources": [:],
                    "prompts": [:]
                ],
                "serverInfo": [
                    "name": "mcp-aha",
                    "version": "1.0.0"
                ]
            ]
        ]
        return toJSON(response)
    }

    private func toolsListResponse(endpoints eps: [APIEndpoint], id: Any?) -> String? {
        let tools = eps.map { endpoint -> [String: Any] in
            let desc = endpoint.description.isEmpty
                ? "\(endpoint.method.rawValue) \(endpoint.path)"
                : endpoint.description
            return [
                "name": endpoint.name.replacingOccurrences(of: " ", with: "_"),
                "description": desc,
                "inputSchema": endpoint.parsedInputSchema
            ]
        }
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": ["tools": tools]
        ]
        return toJSON(response)
    }

    private func toolsCallResponse(endpoints eps: [APIEndpoint], params: [String: Any]?, id: Any?) -> String? {
        guard let params = params,
              let toolName = params["name"] as? String,
              let arguments = params["arguments"] as? [String: Any] else {
            return errorResponse(code: -32602, message: "Invalid params", id: id)
        }

        let endpointName = toolName.replacingOccurrences(of: "_", with: " ")
        guard let endpoint = eps.first(where: { $0.name == endpointName }) else {
            log("  ✗ 工具不存在: \(toolName)")
            return errorResponse(code: -32601, message: "Tool not found", id: id)
        }

        if let argsStr = toCompactJSON(arguments) {
            log("  ↪ 工具参数: \(argsStr)")
        }

        // 执行 JS 转化
        let requestParams = jsEngine.transform(
            script: endpoint.requestTransform,
            input: arguments
        )

        // 调用后端 API
        let apiResponse = callAPI(endpoint: endpoint, params: requestParams)

        // 执行响应 JS 转化
        let result = jsEngine.transform(
            script: endpoint.responseTransform,
            input: apiResponse
        )

        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": [
                "content": [
                    [
                        "type": "text",
                        "text": toJSONString(result)
                    ]
                ]
            ]
        ]
        return toJSON(response)
    }

    private func callAPI(endpoint: APIEndpoint, params: [String: Any]) -> [String: Any] {
        let profile = serverProfiles.first { $0.id == endpoint.serverID }
        let baseURL = profile?.baseURL ?? ""

        guard !baseURL.isEmpty else {
            let msg = "该 API 未配置服务器地址，请在 API 详情中选择服务器"
            log("  ✗ \(msg)")
            return ["error": msg]
        }

        // 构建路径：替换路径参数 {key}
        var path = endpoint.path
        if let pathParams = params["_path"] as? [String: Any] {
            for (key, value) in pathParams {
                path = path.replacingOccurrences(of: "{\(key)}", with: "\(value)")
            }
        }

        // 构建 URL + query 参数
        var urlString = "\(baseURL)\(path)"
        if let queryParams = params["_query"] as? [String: Any], !queryParams.isEmpty {
            var components = URLComponents(string: urlString)!
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
            urlString = components.string ?? urlString
        }

        guard let url = URL(string: urlString) else {
            log("  ✗ 无效 URL: \(urlString)")
            return ["error": "Invalid URL: \(urlString)"]
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 前置鉴权：按需获取/刷新 token
        let authResp = profile.flatMap { resolveAuthToken(for: $0) }

        // 应用自定义 Headers（支持 ${AUTH_RESPONSE.xxx} 变量替换）
        var appliedHeaders: [String: String] = [:]
        for (key, value) in (profile?.parsedHeaders ?? [:]) {
            let resolved = interpolate(value, authResponse: authResp)
            request.setValue(resolved, forHTTPHeaderField: key)
            appliedHeaders[key] = resolved
        }

        // 请求体
        let bodyParams: [String: Any]
        if let body = params["_body"] as? [String: Any] {
            bodyParams = body
        } else if params["_path"] != nil || params["_query"] != nil {
            bodyParams = [:]
        } else {
            bodyParams = params
        }

        if !bodyParams.isEmpty {
            request.httpBody = try? JSONSerialization.data(withJSONObject: bodyParams)
        }

        // 记录 API 请求日志
        log("  → API \(endpoint.method.rawValue) \(urlString)")
        if !appliedHeaders.isEmpty,
           let hStr = toCompactJSON(appliedHeaders as [String: Any]) {
            log("  → Headers: \(hStr)")
        }
        // 检测未解析的 ${AUTH_RESPONSE.xxx} 占位符
        for (key, value) in appliedHeaders where value.contains("${AUTH_RESPONSE.") {
            log("  ⚠ Header '\(key)' 变量未替换: \(value)")
            log("    → 可能原因: ①鉴权响应中没有该字段 ②鉴权请求失败（见上方鉴权日志）")
        }
        if !bodyParams.isEmpty, let bStr = toCompactJSON(bodyParams) {
            log("  → 请求体: \(bStr)")
        }

        // 同步发起请求
        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any] = [:]
        var httpStatus: Int = 0

        URLSession.shared.dataTask(with: request) { data, response, error in
            httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result = json
            } else if let data = data, let raw = String(data: data, encoding: .utf8) {
                result = ["rawResponse": raw]
            } else if let error = error {
                result = ["error": error.localizedDescription]
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()

        // 记录 API 响应日志
        let statusTag = httpStatus > 0 ? " HTTP \(httpStatus)" : ""
        if let rStr = toCompactJSON(result) {
            log("  ← 响应\(statusTag): \(rStr)")
        } else {
            log("  ← 响应\(statusTag): (空)")
        }

        return result
    }

    // MARK: - Auth helpers

    /// 按缓存 + 过期时间决定是否需要重新鉴权，返回鉴权响应 dict
    private func resolveAuthToken(for profile: ServerProfile) -> [String: Any]? {
        guard profile.authMode == .clientCredentials else { return nil }

        // 提前校验配置
        let trimmedBody = profile.authBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if profile.authURL.isEmpty {
            log("  ↪ [鉴权] ✗ 未配置鉴权请求地址，请在服务器配置中填写")
            return nil
        }
        if trimmedBody.isEmpty || trimmedBody == "{}" {
            log("  ↪ [鉴权] ⚠ 鉴权请求体为空（当前值: \(trimmedBody)），服务器可能会拒绝请求")
        }

        if let cached = AuthTokenCache.shared.get(for: profile.id, expiryMinutes: profile.authExpiry) {
            log("  ↪ [鉴权] 使用缓存 Token（过期时间: \(profile.authExpiry) 分钟 / 服务器: \(profile.name)）")
            return cached
        }
        log("  ↪ [鉴权] Token 不存在或已过期，开始获取...（服务器: \(profile.name)）")
        guard let fresh = fetchAuthToken(profile: profile) else { return nil }

        // 检测错误响应 —— 有 errorCode 且非 0，则不缓存，并打印详细错误
        if let code = fresh["errorCode"] as? Int, code != 0 {
            let msg = fresh["errorMessage"] as? String ?? "（无 errorMessage）"
            log("  ↪ [鉴权] ✗ 接口返回业务错误 errorCode=\(code): \(msg)，Token 未缓存")
            return fresh   // 仍然返回，让 interpolate 处理，避免占位符残留的假象
        }

        AuthTokenCache.shared.set(for: profile.id, response: fresh)
        log("  ↪ [鉴权] ✓ Token 获取成功，已缓存（过期时间: \(profile.authExpiry) 分钟）")
        return fresh
    }

    /// 同步发起鉴权请求，返回完整 response JSON
    private func fetchAuthToken(profile: ServerProfile) -> [String: Any]? {
        guard !profile.authURL.isEmpty else {
            log("  ↪ [鉴权] ✗ 鉴权请求地址为空，请在服务器配置中填写鉴权 URL")
            return nil
        }
        guard let url = URL(string: profile.authURL) else {
            log("  ↪ [鉴权] ✗ 无效的鉴权 URL: \(profile.authURL)")
            return nil
        }
        guard let body = profile.authBody.data(using: .utf8) else {
            log("  ↪ [鉴权] ✗ 请求体编码失败")
            return nil
        }

        log("  ↪ [鉴权] POST \(profile.authURL)")
        log("  ↪ [鉴权] 请求体: \(profile.authBody.trimmingCharacters(in: .whitespacesAndNewlines))")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any]?
        var httpStatus: Int = 0

        URLSession.shared.dataTask(with: req) { data, response, error in
            httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result = json
            } else if let data = data, let raw = String(data: data, encoding: .utf8) {
                result = ["rawResponse": raw]
            } else if let error = error {
                result = ["error": error.localizedDescription]
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()

        let statusTag = httpStatus > 0 ? " HTTP \(httpStatus)" : ""
        if let r = result, let rStr = toCompactJSON(r) {
            log("  ↪ [鉴权响应\(statusTag)] \(rStr)")
        } else {
            log("  ↪ [鉴权响应\(statusTag)] ✗ 无响应或响应解析失败")
        }

        return result
    }

    /// 把 Header 值中的 ${AUTH_RESPONSE.xxx} 替换为鉴权响应字段值
    /// key 找不到时保留原始占位符（而非替换成空串），便于日志发现问题
    private func interpolate(_ template: String, authResponse: [String: Any]?) -> String {
        guard let auth = authResponse, template.contains("${AUTH_RESPONSE.") else { return template }
        var result = template
        guard let regex = try? NSRegularExpression(pattern: #"\$\{AUTH_RESPONSE\.([^}]+)\}"#) else { return result }
        let ns      = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let keyRange = match.range(at: 1)
            guard keyRange.location != NSNotFound else { continue }
            let key = ns.substring(with: keyRange)
            // key 存在才替换，找不到时保留 ${AUTH_RESPONSE.xxx} 占位符
            if let anyValue = auth[key] {
                result = (result as NSString).replacingCharacters(in: match.range, with: "\(anyValue)")
            }
        }
        return result
    }

    /// 将任意 dict 序列化为紧凑 JSON 字符串（用于日志）
    private func toCompactJSON(_ obj: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let str  = String(data: data, encoding: .utf8) else { return nil }
        // 超过 500 字符时截断，避免日志过长
        return str.count > 500 ? String(str.prefix(500)) + "…" : str
    }

    private func handleSSE() -> String? {
        return nil // SSE 已废弃，不再支持
    }

    private func httpResponse(status: Int, body: String) -> String {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }
        return "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
    }

    private func errorResponse(code: Int, message: String, id: Any? = nil) -> String? {
        // 使用 NSNull 来表示 JSON null 值
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ]
        return toJSON(response)
    }

    // MARK: - Resources

    private func resourcesListResponse(endpoints eps: [APIEndpoint], id: Any?) -> String? {
        let resources: [[String: Any]] = eps.compactMap { endpoint -> [String: Any]? in
            guard endpoint.isEnabled else { return nil }
            return [
                "uri": "endpoint://\(endpoint.name.replacingOccurrences(of: " ", with: "_"))",
                "name": endpoint.name,
                "description": "\(endpoint.method.rawValue) \(endpoint.path)",
                "mimeType": "application/json"
            ]
        }
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": ["resources": resources]
        ]
        return toJSON(response)
    }

    private func resourcesReadResponse(endpoints eps: [APIEndpoint], params: [String: Any]?, id: Any?) -> String? {
        guard let uri = params?["uri"] as? String else {
            return errorResponse(code: -32602, message: "Missing uri parameter", id: id)
        }

        let endpointName = uri.replacingOccurrences(of: "endpoint://", with: "").replacingOccurrences(of: "_", with: " ")
        guard let endpoint = eps.first(where: { $0.name == endpointName }) else {
            return errorResponse(code: -32601, message: "Resource not found", id: id)
        }

        let content: [String: Any] = [
            "uri": uri,
            "mimeType": "application/json",
            "text": "{\"method\": \"\(endpoint.method.rawValue)\", \"path\": \"\(endpoint.path)\"}"
        ]

        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": ["contents": [content]]
        ]
        return toJSON(response)
    }

    // MARK: - Prompts

    private func promptsListResponse(id: Any?) -> String? {
        // 返回可用的提示模板
        let prompts: [[String: Any]] = [
            [
                "name": "api_call",
                "description": "调用 API 端点",
                "arguments": [
                    [
                        "name": "endpoint",
                        "description": "API 端点名称",
                        "required": true,
                        "type": "string"
                    ],
                    [
                        "name": "params",
                        "description": "请求参数",
                        "required": false,
                        "type": "object"
                    ]
                ]
            ]
        ]

        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": ["prompts": prompts]
        ]
        return toJSON(response)
    }

    private func promptsGetResponse(params: [String: Any]?, id: Any?) -> String? {
        guard let name = params?["name"] as? String else {
            return errorResponse(code: -32602, message: "Missing name parameter", id: id)
        }

        let arguments = params?["arguments"] as? [String: Any] ?? [:]

        switch name {
        case "api_call":
            let endpointName = arguments["endpoint"] as? String ?? "default"
            let callParams = arguments["params"] as? [String: Any] ?? [:]

            let messages: [[String: Any]] = [
                [
                    "role": "user",
                    "content": [
                        "type": "text",
                        "text": "调用 API: \(endpointName)，参数: \(toJSONString(callParams))"
                    ]
                ]
            ]

            let response: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "result": ["messages": messages]
            ]
            return toJSON(response)
        default:
            return errorResponse(code: -32601, message: "Prompt not found", id: id)
        }
    }

    // MARK: - Logging

    private func loggingSetLevelResponse(params: [String: Any]?, id: Any?) -> String? {
        let level = params?["level"] as? String ?? "info"

        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": ["level": level]
        ]
        return toJSON(response)
    }

    // MARK: - Ping

    private func pingResponse(id: Any?) -> String? {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": [:]
        ]
        return toJSON(response)
    }

    private func toJSON(_ dict: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func toJSONString(_ value: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: value),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}

enum ServerError: LocalizedError {
    case invalidConfig
    case startFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfig:
            return "配置无效"
        case .startFailed:
            return "启动失败"
        }
    }
}

// MARK: - AuthTokenCache（内存缓存，线程安全）

final class AuthTokenCache {
    static let shared = AuthTokenCache()
    private init() {}

    private struct Entry {
        let response:  [String: Any]
        let fetchedAt: Date
    }

    private var cache: [UUID: Entry] = [:]
    private let lock  = NSLock()

    /// 返回未过期的缓存；nil 表示不存在或已过期
    func get(for profileID: UUID, expiryMinutes: Int) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache[profileID] else { return nil }
        let elapsedMin = Date().timeIntervalSince(entry.fetchedAt) / 60.0
        if elapsedMin >= Double(expiryMinutes) {
            cache.removeValue(forKey: profileID)
            return nil
        }
        return entry.response
    }

    func set(for profileID: UUID, response: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        cache[profileID] = Entry(response: response, fetchedAt: Date())
    }

    func invalidate(for profileID: UUID) {
        lock.lock(); defer { lock.unlock() }
        cache.removeValue(forKey: profileID)
    }
}
