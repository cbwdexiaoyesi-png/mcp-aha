import SwiftUI

// MARK: - Group filter

enum GroupFilter: Equatable {
    case all
    case ungrouped
    case group(UUID)
}

// MARK: - APIListView

struct APIListView: View {
    @StateObject private var store = EndpointStore.shared
    @State private var selectedID: UUID?

    var filter: GroupFilter = .all

    private var filteredEndpoints: [APIEndpoint] {
        switch filter {
        case .all:
            return store.endpoints
        case .ungrouped:
            return store.endpoints.filter { $0.groupID == nil }
        case .group(let id):
            return store.endpoints.filter { $0.groupID == id }
        }
    }

    private var selectedEndpoint: APIEndpoint? {
        store.endpoints.first { $0.id == selectedID }
    }

    var body: some View {
        HSplitView {
            List(selection: $selectedID) {
                ForEach(filteredEndpoints) { endpoint in
                    EndpointRow(endpoint: endpoint)
                        .tag(endpoint.id)
                }
                .onMove(perform: moveFiltered)
                .onDelete(perform: deleteFiltered)
            }
            .listStyle(.inset)
            .frame(minWidth: 160, idealWidth: 200, maxWidth: 280)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addNew) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(action: deleteSelected) {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedID == nil)
                }
            }

            if let endpoint = selectedEndpoint {
                EndpointDetailView(endpoint: endpoint)
                    .id(endpoint.id)
                    .frame(minWidth: 400)
            } else {
                Text("选择一个 API 进行编辑")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // 当过滤列表变化时，若当前选中的 API 不在列表里则清除选中
        .onChange(of: filter) { _ in
            if let id = selectedID,
               !filteredEndpoints.contains(where: { $0.id == id }) {
                selectedID = nil
            }
        }
    }

    private func addNew() {
        var newEndpoint = APIEndpoint(name: "新 API", path: "/api/example")
        if case .group(let id) = filter {
            newEndpoint.groupID = id
        }
        store.add(newEndpoint)
        selectedID = newEndpoint.id
    }

    /// onDelete 只操作当前过滤结果的偏移量
    private func deleteFiltered(at offsets: IndexSet) {
        let toDelete = offsets.map { filteredEndpoints[$0] }
        toDelete.forEach { store.delete($0) }
    }

    /// onMove 同理，只在过滤列表内移动（全部列表时与 store 直接对应）
    private func moveFiltered(from source: IndexSet, to destination: Int) {
        if filter == .all {
            store.move(from: source, to: destination)
        }
        // 分组过滤时暂不支持跨分组拖动排序（视觉上隐藏 onMove 手柄）
    }

    private func deleteSelected() {
        if let endpoint = selectedEndpoint {
            store.delete(endpoint)
            selectedID = nil
        }
    }
}

// MARK: - Endpoint row

struct EndpointRow: View {
    let endpoint: APIEndpoint

    var body: some View {
        HStack {
            Image(systemName: endpoint.isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundColor(endpoint.isEnabled ? .green : .gray)

            VStack(alignment: .leading) {
                Text(endpoint.name)
                    .fontWeight(.medium)
                Text(endpoint.method.rawValue + " " + endpoint.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Endpoint detail

struct EndpointDetailView: View {
    @ObservedObject var store         = EndpointStore.shared
    @ObservedObject var groupStore    = GroupStore.shared
    @ObservedObject var serverStore   = ServerProfileStore.shared
    let endpoint: APIEndpoint
    @State private var editedEndpoint: APIEndpoint
    @State private var showAPITest = false

    init(endpoint: APIEndpoint) {
        self.endpoint = endpoint
        self._editedEndpoint = State(initialValue: endpoint)
    }

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称", text: $editedEndpoint.name)
                TextField("描述（作为 MCP Tool 的 description）", text: $editedEndpoint.description)
                TextField("路径", text: $editedEndpoint.path)
                Picker("方法", selection: $editedEndpoint.method) {
                    ForEach(HTTPMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                // 服务器选择器
                Picker("服务器", selection: $editedEndpoint.serverID) {
                    Text("未指定").tag(UUID?.none)
                    ForEach(serverStore.profiles) { profile in
                        HStack {
                            Text(profile.name)
                            Text(profile.baseURL)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .tag(UUID?.some(profile.id))
                    }
                }
                // 分组选择器
                Picker("分组", selection: $editedEndpoint.groupID) {
                    Text("未分组").tag(UUID?.none)
                    ForEach(groupStore.groups) { group in
                        Text(group.name).tag(UUID?.some(group.id))
                    }
                }
                Toggle("启用", isOn: $editedEndpoint.isEnabled)
            }

            Section {
                HStack {
                    Text("MCP 参数 Schema (JSON)")
                        .font(.headline)
                    Spacer()
                    if editedEndpoint.isSchemaValid {
                        Label("合法", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Label("JSON 格式错误", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                .padding(.bottom, 2)

                ExpandableCodeEditor(
                    text: $editedEndpoint.inputSchema,
                    language: .json,
                    title: "MCP 参数 Schema (JSON)"
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("遵循 JSON Schema 规范，定义 MCP Tool 的输入参数，AI 会根据此 Schema 传参。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    DisclosureGroup("查看配置说明") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("""
**基本结构**
```json
{
  "type": "object",
  "properties": { ... },
  "required": ["必填字段1", "必填字段2"]
}
```

**字段类型 (type)**
• `"string"` — 字符串
• `"number"` — 数字（含小数）
• `"integer"` — 整数
• `"boolean"` — 布尔值 true/false
• `"array"` — 数组
• `"object"` — 对象

**常用属性**
• `description` — 字段说明，AI 会参考这个描述来传参
• `enum` — 枚举值，如 `["�active", "inactive"]`
• `default` — 默认值
• `minLength` / `maxLength` — 字符串长度限制
• `minimum` / `maximum` — 数字范围限制

**示例**
```json
{
  "type": "object",
  "properties": {
    "userId": {
      "type": "string",
      "description": "用户ID"
    },
    "status": {
      "type": "string",
      "enum": ["active", "inactive"],
      "description": "用户状态"
    },
    "limit": {
      "type": "integer",
      "default": 10,
      "minimum": 1,
      "maximum": 100,
      "description": "返回数量限制"
    }
  },
  "required": ["userId"]
}
```
""")
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Section("请求参数转化 (JavaScript)") {
                ExpandableCodeEditor(
                    text: $editedEndpoint.requestTransform,
                    language: .javascript,
                    title: "请求参数转化 (JavaScript)"
                )
            }

            Section("响应数据转化 (JavaScript)") {
                ExpandableCodeEditor(
                    text: $editedEndpoint.responseTransform,
                    language: .javascript,
                    title: "响应数据转化 (JavaScript)"
                )
            }

            Section {
                HStack {
                    Button("保存") {
                        store.update(editedEndpoint)
                    }
                    .disabled(editedEndpoint.name.isEmpty || editedEndpoint.path.isEmpty)
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button {
                        showAPITest = true
                    } label: {
                        Label("测试 API", systemImage: "play.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(editedEndpoint.serverID == nil)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: endpoint) { newEndpoint in
            editedEndpoint = newEndpoint
        }
        .sheet(isPresented: $showAPITest) {
            APITestView(endpoint: editedEndpoint, serverStore: serverStore)
        }
    }
}

// MARK: - API Test View

struct APITestView: View {
    let endpoint: APIEndpoint
    let serverStore: ServerProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var testParams: String = "{}"
    @State private var isLoading = false

    // 请求详情
    @State private var reqMethod: String = ""
    @State private var reqURL: String = ""
    @State private var reqHeaders: String = ""
    @State private var reqBody: String = ""

    // 响应详情
    @State private var respStatus: String = ""
    @State private var respBody: String = ""

    // 鉴权详情
    @State private var authLog: String = ""

    private var profile: ServerProfile? {
        serverStore.profiles.first { $0.id == endpoint.serverID }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("API 测试").font(.headline)
                    Text("\(endpoint.method.rawValue) \(endpoint.path)")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            HSplitView {
                // 左侧：输入参数
                VStack(alignment: .leading, spacing: 8) {
                    Text("输入参数 (MCP Tool Arguments)").font(.caption).foregroundColor(.secondary)
                    SyntaxEditor(text: $testParams, language: .json)
                        .frame(maxHeight: .infinity)

                    Button {
                        sendTestRequest()
                    } label: {
                        Label("发送请求", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                }
                .padding()
                .frame(minWidth: 280)

                // 右侧：请求/响应详情
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 鉴权日志
                        if !authLog.isEmpty {
                            GroupBox {
                                Text(authLog)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } label: {
                                Label("鉴权", systemImage: "lock.circle")
                            }
                        }

                        // 请求详情
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                if reqURL.isEmpty && !isLoading {
                                    Text("点击「发送请求」查看详情")
                                        .foregroundColor(.secondary)
                                } else if isLoading {
                                    HStack {
                                        ProgressView().controlSize(.small)
                                        Text("请求中...").foregroundColor(.secondary)
                                    }
                                } else {
                                    HStack {
                                        Text(reqMethod).fontWeight(.semibold).foregroundColor(.blue)
                                        Text(reqURL).font(.system(.caption, design: .monospaced))
                                        Spacer()
                                    }

                                    Divider()

                                    Text("请求头").font(.caption).foregroundColor(.secondary)
                                    Text(reqHeaders)
                                        .font(.system(.caption2, design: .monospaced))
                                        .textSelection(.enabled)

                                    if !reqBody.isEmpty {
                                        Divider()
                                        Text("请求体").font(.caption).foregroundColor(.secondary)
                                        Text(reqBody)
                                            .font(.system(.caption2, design: .monospaced))
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("请求", systemImage: "arrow.up.circle")
                        }

                        // 响应详情
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                if respBody.isEmpty && !isLoading {
                                    Text("等待响应...")
                                        .foregroundColor(.secondary)
                                } else {
                                    HStack {
                                        Text("状态").font(.caption).foregroundColor(.secondary)
                                        Text(respStatus)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(respStatus.contains("200") ? .green : .orange)
                                    }

                                    Divider()

                                    Text("响应体").font(.caption).foregroundColor(.secondary)
                                    Text(respBody)
                                        .font(.system(.caption2, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("响应", systemImage: "arrow.down.circle")
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 400)
            }
        }
        .frame(width: 900, height: 600)
        .onAppear {
            // 预填默认参数
            testParams = endpoint.inputSchema.isEmpty ? "{}" : generateSampleParams()
        }
    }

    private func generateSampleParams() -> String {
        // 尝试从 inputSchema 生成示例参数
        guard let data = endpoint.inputSchema.data(using: .utf8),
              let schema = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = schema["properties"] as? [String: Any] else {
            return "{}"
        }
        var sample: [String: Any] = [:]
        for (key, value) in props {
            if let prop = value as? [String: Any] {
                let type = prop["type"] as? String ?? "string"
                switch type {
                case "string":  sample[key] = ""
                case "number", "integer": sample[key] = 0
                case "boolean": sample[key] = false
                case "array":   sample[key] = []
                case "object":  sample[key] = [:]
                default:        sample[key] = ""
                }
            }
        }
        if let pretty = try? JSONSerialization.data(withJSONObject: sample, options: .prettyPrinted),
           let str = String(data: pretty, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private func sendTestRequest() {
        guard let profile = profile else {
            respBody = "错误: 未选择服务器"
            return
        }

        isLoading = true
        authLog = ""
        reqURL = ""
        reqHeaders = ""
        reqBody = ""
        respStatus = ""
        respBody = ""

        DispatchQueue.global(qos: .userInitiated).async {
            // 解析输入参数
            let inputParams: [String: Any]
            if let data = testParams.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                inputParams = json
            } else {
                inputParams = [:]
            }

            // 执行请求转换脚本
            let jsEngine = JSEngine()
            let transformedParams = jsEngine.transform(script: endpoint.requestTransform, input: inputParams)

            // 构建 URL
            var path = endpoint.path
            if let pathParams = transformedParams["_path"] as? [String: Any] {
                for (key, value) in pathParams {
                    path = path.replacingOccurrences(of: "{\(key)}", with: "\(value)")
                }
            }

            var urlString = "\(profile.baseURL)\(path)"
            if let queryParams = transformedParams["_query"] as? [String: Any], !queryParams.isEmpty {
                var components = URLComponents(string: urlString)!
                components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
                urlString = components.string ?? urlString
            }

            guard let url = URL(string: urlString) else {
                DispatchQueue.main.async {
                    isLoading = false
                    respBody = "错误: 无效 URL \(urlString)"
                }
                return
            }

            // 鉴权
            var authResponse: [String: Any]?
            if profile.authMode == .clientCredentials && !profile.authURL.isEmpty {
                DispatchQueue.main.async {
                    authLog = "正在获取 Token..."
                }

                if let authURL = URL(string: profile.authURL),
                   let authBodyData = profile.authBody.data(using: .utf8) {
                    var authReq = URLRequest(url: authURL)
                    authReq.httpMethod = "POST"
                    authReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    authReq.httpBody = authBodyData

                    let semaphore = DispatchSemaphore(value: 0)
                    URLSession.shared.dataTask(with: authReq) { data, response, error in
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            authResponse = json
                            let pretty = (try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted))
                                .flatMap { String(data: $0, encoding: .utf8) } ?? "\(json)"
                            DispatchQueue.main.async {
                                authLog = "POST \(profile.authURL)\nHTTP \(status)\n\n\(pretty)"
                            }
                        } else if let error = error {
                            DispatchQueue.main.async {
                                authLog = "鉴权失败: \(error.localizedDescription)"
                            }
                        }
                        semaphore.signal()
                    }.resume()
                    semaphore.wait()
                }
            }

            // 构建请求
            var request = URLRequest(url: url)
            request.httpMethod = endpoint.method.rawValue
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // 应用 headers（变量替换）
            var headersDisplay: [String] = ["Content-Type: application/json"]
            for (key, value) in profile.parsedHeaders {
                let resolved = interpolate(value, authResponse: authResponse)
                request.setValue(resolved, forHTTPHeaderField: key)
                headersDisplay.append("\(key): \(resolved)")
            }

            // 请求体
            let bodyParams: [String: Any]
            if let body = transformedParams["_body"] as? [String: Any] {
                bodyParams = body
            } else if transformedParams["_path"] != nil || transformedParams["_query"] != nil {
                bodyParams = [:]
            } else {
                bodyParams = transformedParams
            }

            var bodyDisplay = ""
            if !bodyParams.isEmpty {
                request.httpBody = try? JSONSerialization.data(withJSONObject: bodyParams)
                if let pretty = try? JSONSerialization.data(withJSONObject: bodyParams, options: .prettyPrinted),
                   let str = String(data: pretty, encoding: .utf8) {
                    bodyDisplay = str
                }
            }

            DispatchQueue.main.async {
                reqMethod = endpoint.method.rawValue
                reqURL = urlString
                reqHeaders = headersDisplay.joined(separator: "\n")
                reqBody = bodyDisplay
            }

            // 发送请求
            let semaphore = DispatchSemaphore(value: 0)
            var finalStatus = ""
            var finalBody = ""

            URLSession.shared.dataTask(with: request) { data, response, error in
                let httpResp = response as? HTTPURLResponse
                finalStatus = httpResp.map { "HTTP \($0.statusCode)" } ?? "无响应"

                if let data = data {
                    if let json = try? JSONSerialization.jsonObject(with: data),
                       let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                       let str = String(data: pretty, encoding: .utf8) {
                        finalBody = str
                    } else if let str = String(data: data, encoding: .utf8) {
                        finalBody = str
                    } else {
                        finalBody = "（二进制数据 \(data.count) 字节）"
                    }
                } else if let error = error {
                    finalBody = "错误: \(error.localizedDescription)"
                }
                semaphore.signal()
            }.resume()
            semaphore.wait()

            DispatchQueue.main.async {
                isLoading = false
                respStatus = finalStatus
                respBody = finalBody
            }
        }
    }

    private func interpolate(_ template: String, authResponse: [String: Any]?) -> String {
        guard let auth = authResponse, template.contains("${AUTH_RESPONSE.") else { return template }
        var result = template
        guard let regex = try? NSRegularExpression(pattern: #"\$\{AUTH_RESPONSE\.([^}]+)\}"#) else { return result }
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let keyRange = match.range(at: 1)
            guard keyRange.location != NSNotFound else { continue }
            let key = ns.substring(with: keyRange)
            if let value = auth[key] {
                result = (result as NSString).replacingCharacters(in: match.range, with: "\(value)")
            }
        }
        return result
    }
}
