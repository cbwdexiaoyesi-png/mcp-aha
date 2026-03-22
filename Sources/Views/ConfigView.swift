import SwiftUI

// MARK: - ConfigView (Server profile manager)

struct ConfigView: View {
    @StateObject private var store = ServerProfileStore.shared
    @State private var selectedID: UUID?

    private var selectedProfile: ServerProfile? {
        store.profiles.first { $0.id == selectedID }
    }

    var body: some View {
        HSplitView {
            // ── 左侧：服务器列表 ──
            List(selection: $selectedID) {
                ForEach(store.profiles) { profile in
                    ServerRow(profile: profile)
                        .tag(profile.id)
                }
                .onDelete(perform: deleteProfiles)
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

            // ── 右侧：详情 ──
            if let profile = selectedProfile {
                ServerProfileDetailView(profile: profile)
                    .id(profile.id)
                    .frame(minWidth: 380)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("选择或新建一个服务器")
                        .foregroundColor(.secondary)
                    Button("新建服务器", action: addNew)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func addNew() {
        let p = ServerProfile(name: "新服务器")
        store.add(p)
        selectedID = p.id
    }

    private func deleteProfiles(at offsets: IndexSet) {
        offsets.map { store.profiles[$0] }.forEach { store.delete($0) }
    }

    private func deleteSelected() {
        if let p = selectedProfile {
            store.delete(p)
            selectedID = nil
        }
    }
}

// MARK: - Server list row

struct ServerRow: View {
    let profile: ServerProfile

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: profile.isValid ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(profile.isValid ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .fontWeight(.medium)
                Text(profile.baseURL.isEmpty ? "未配置地址" : profile.baseURL)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Server profile detail form

struct ServerProfileDetailView: View {
    @ObservedObject private var store = ServerProfileStore.shared
    let profile: ServerProfile
    @State private var edited: ServerProfile
    @State private var showAuthTest = false

    init(profile: ServerProfile) {
        self.profile = profile
        self._edited = State(initialValue: profile)
    }

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称", text: $edited.name)
                    .textFieldStyle(.roundedBorder)
            }

            Section("后端服务器") {
                TextField("基础地址（如 https://api.example.com）", text: $edited.baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            // ── 前置鉴权 ──────────────────────────────
            Section {
                HStack {
                    Text("前置鉴权").font(.headline)
                    Spacer()
                    if edited.authMode != .none {
                        Label("已启用", systemImage: "lock.fill")
                            .foregroundColor(.blue).font(.caption)
                    }
                }
                .padding(.bottom, 2)

                Picker("鉴权模式", selection: $edited.authMode) {
                    ForEach(AuthMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if edited.authMode == .clientCredentials {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("鉴权请求地址（POST）", text: $edited.authURL)
                            .textFieldStyle(.roundedBorder)

                        Text("请求体 (JSON)").font(.caption).foregroundColor(.secondary)
                        ExpandableCodeEditor(
                            text: $edited.authBody,
                            language: .json,
                            title: "鉴权请求体 (JSON)"
                        )

                        HStack(spacing: 8) {
                            Text("Token 过期时间").font(.callout)
                            Spacer()
                            Stepper(value: $edited.authExpiry, in: 1...10080, step: 5) {
                                Text("\(edited.authExpiry) 分钟")
                                    .monospacedDigit()
                                    .frame(minWidth: 72, alignment: .trailing)
                            }
                        }
                        .padding(.top, 2)

                        Text("调用 MCP 工具时若 Token 不存在或已超过过期时间，将自动发起此鉴权请求后再调用 API。")
                            .font(.caption2).foregroundColor(.secondary)

                        HStack {
                            Spacer()
                            Button {
                                showAuthTest = true
                            } label: {
                                Label("测试鉴权", systemImage: "play.circle")
                            }
                            .buttonStyle(.bordered)
                            .disabled(edited.authURL.isEmpty)
                        }
                        .padding(.top, 6)
                    }
                    .padding(.top, 4)
                }
            }

            // ── 请求 Headers ────────────────────────
            Section {
                HStack {
                    Text("请求 Headers (JSON)")
                        .font(.headline)
                    Spacer()
                    if edited.isHeadersValid {
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
                    text: $edited.headers,
                    language: .json,
                    title: "请求 Headers (JSON)"
                )

                if edited.authMode == .clientCredentials {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle").foregroundColor(.blue).font(.caption)
                        Text("可在 Header 值中使用 **${AUTH_RESPONSE.字段名}** 引用鉴权响应，例如：\n`{\"Authorization\": \"Bearer ${AUTH_RESPONSE.accessToken}\"}`")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                } else {
                    Text("所有经此服务器发出的 API 请求都会携带这些 Headers，可用于鉴权或自定义请求头。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Section {
                Button("保存") {
                    store.update(edited)
                }
                .disabled(edited.name.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onChange(of: profile) { newProfile in
            edited = newProfile
        }
        .sheet(isPresented: $showAuthTest) {
            AuthTestView(profile: edited)
        }
    }
}

// MARK: - Auth Test View

struct AuthTestView: View {
    let profile: ServerProfile
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var requestHeaders: String = ""
    @State private var requestBody: String = ""
    @State private var responseStatus: String = ""
    @State private var responseBody: String = ""
    @State private var interpolatedHeaders: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("鉴权测试").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 请求信息
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("POST").fontWeight(.semibold).foregroundColor(.blue)
                                Text(profile.authURL).font(.system(.body, design: .monospaced))
                                Spacer()
                            }

                            Divider()

                            Text("请求头").font(.caption).foregroundColor(.secondary)
                            Text(requestHeaders.isEmpty ? "Content-Type: application/json" : requestHeaders)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)

                            Divider()

                            Text("请求体").font(.caption).foregroundColor(.secondary)
                            Text(requestBody.isEmpty ? profile.authBody : requestBody)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("请求", systemImage: "arrow.up.circle")
                    }

                    // 响应信息
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            if isLoading {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("请求中...").foregroundColor(.secondary)
                                }
                            } else if responseBody.isEmpty {
                                Text("点击「发送请求」查看响应")
                                    .foregroundColor(.secondary)
                            } else {
                                HStack {
                                    Text("状态").font(.caption).foregroundColor(.secondary)
                                    Text(responseStatus)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(responseStatus.hasPrefix("2") ? .green : .red)
                                }

                                Divider()

                                Text("响应体").font(.caption).foregroundColor(.secondary)
                                Text(responseBody)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("响应", systemImage: "arrow.down.circle")
                    }

                    // Headers 变量替换预览
                    if !responseBody.isEmpty && profile.authMode == .clientCredentials {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("原始 Headers 配置").font(.caption).foregroundColor(.secondary)
                                Text(profile.headers)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Divider()

                                Text("替换 ${AUTH_RESPONSE.xxx} 后").font(.caption).foregroundColor(.secondary)
                                Text(interpolatedHeaders)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Headers 变量预览", systemImage: "text.badge.checkmark")
                        }
                    }
                }
                .padding()
            }

            Divider()

            // 底部按钮
            HStack {
                Spacer()
                Button {
                    sendAuthRequest()
                } label: {
                    Label("发送请求", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || profile.authURL.isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 550)
        .onAppear {
            requestBody = profile.authBody
        }
    }

    private func sendAuthRequest() {
        guard let url = URL(string: profile.authURL) else {
            responseStatus = "无效 URL"
            return
        }

        isLoading = true
        responseBody = ""
        responseStatus = ""
        interpolatedHeaders = ""

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = profile.authBody.data(using: .utf8)

        requestHeaders = "Content-Type: application/json"
        requestBody = profile.authBody

        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                let httpResp = response as? HTTPURLResponse
                responseStatus = httpResp.map { "HTTP \($0.statusCode)" } ?? "无响应"

                if let data = data, let str = String(data: data, encoding: .utf8) {
                    // 格式化 JSON
                    if let json = try? JSONSerialization.jsonObject(with: data),
                       let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                       let prettyStr = String(data: pretty, encoding: .utf8) {
                        responseBody = prettyStr
                        // 计算 interpolated headers
                        if let dict = json as? [String: Any] {
                            interpolatedHeaders = interpolateHeaders(profile.headers, authResponse: dict)
                        }
                    } else {
                        responseBody = str
                    }
                } else if let error = error {
                    responseBody = "错误: \(error.localizedDescription)"
                } else {
                    responseBody = "（空响应）"
                }
            }
        }.resume()
    }

    private func interpolateHeaders(_ template: String, authResponse: [String: Any]) -> String {
        var result = template
        guard let regex = try? NSRegularExpression(pattern: #"\$\{AUTH_RESPONSE\.([^}]+)\}"#) else { return result }
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let keyRange = match.range(at: 1)
            guard keyRange.location != NSNotFound else { continue }
            let key = ns.substring(with: keyRange)
            if let value = authResponse[key] {
                result = (result as NSString).replacingCharacters(in: match.range, with: "\(value)")
            }
        }
        return result
    }
}
