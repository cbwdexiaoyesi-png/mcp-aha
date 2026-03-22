import SwiftUI
import Combine

// MARK: - Log entry model

struct LogEntry: Identifiable {
    let id = UUID()
    let raw: String          // original string
    let timestamp: String
    let body: String
    let level: Level

    enum Level { case info, success, error, request }

    static func parse(_ raw: String) -> LogEntry {
        // Format: "[ISO8601] message"
        var ts   = ""
        var body = raw
        if raw.hasPrefix("["), let end = raw.firstIndex(of: "]") {
            ts   = String(raw[raw.index(after: raw.startIndex)..<end])
            body = String(raw[raw.index(after: end)...]).trimmingCharacters(in: .whitespaces)
        }
        let level: Level
        if body.contains("错误") || body.contains("失败") || body.contains("Error") {
            level = .error
        } else if body.contains("启动") || body.contains("成功") {
            level = .success
        } else if body.contains("收到请求") {
            level = .request
        } else {
            level = .info
        }
        return LogEntry(raw: raw, timestamp: ts, body: body, level: level)
    }
}

// MARK: - Import target

enum ImportTarget: Identifiable {
    case cursor, claudeDesktop, claudeCode, generic
    var id: Self { self }

    var title: String {
        switch self {
        case .cursor:        return "Cursor"
        case .claudeDesktop: return "Claude Desktop"
        case .claudeCode:    return "Claude Code"
        case .generic:       return "其他工具"
        }
    }
    var icon: String {
        switch self {
        case .cursor:        return "cursorarrow.click"
        case .claudeDesktop: return "desktopcomputer"
        case .claudeCode:    return "terminal"
        case .generic:       return "doc.on.clipboard"
        }
    }
}

// MARK: - ServerView

struct ServerView: View {
    @StateObject private var appConfig          = AppConfig.shared
    @StateObject private var serverManager      = MCPServerManager.shared
    @StateObject private var serverProfileStore = ServerProfileStore.shared
    @StateObject private var endpointStore      = EndpointStore.shared

    // Logs
    @State private var logs: [LogEntry]  = []
    @State private var currentPage       = 0
    @State private var selectedLog: LogEntry? = nil
    private let logsPerPage = 50

    // Test
    @State private var testRequest  = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
    @State private var testResponse = ""
    @State private var isTesting    = false

    // Import
    @State private var importTarget:  ImportTarget? = nil
    @State private var importToast:   String?       = nil
    @State private var importingURL:  String        = ""

    // ──────────────────────────────────────────
    private var mcpURL: String { "http://127.0.0.1:\(appConfig.mcpConfig.port)/mcp" }
    private var totalToolCount: Int { endpointStore.endpoints.filter { $0.isEnabled }.count }

    private var reversedLogs: [LogEntry] { logs.reversed() }
    private var totalPages: Int { max(1, (logs.count + logsPerPage - 1) / logsPerPage) }
    private var pagedLogs: [LogEntry] {
        let all   = reversedLogs
        let start = currentPage * logsPerPage
        let end   = min(start + logsPerPage, all.count)
        guard start < end else { return [] }
        return Array(all[start..<end])
    }

    // ──────────────────────────────────────────
    var body: some View {
        VStack(spacing: 0) {

            // ── 端口配置（仅停止时显示）
            if !serverManager.isRunning {
                portConfigBar
                Divider()
            }

            // ── 状态栏
            statusBar
            Divider()

            // ── 导入工具栏（运行时显示）
            if serverManager.isRunning {
                importBar
                Divider()
            }

            // ── 测试区域（运行时显示）
            if serverManager.isRunning {
                testPanel
                Divider()
            }

            // ── 日志区域
            logArea
        }
        .onAppear {
            logs = serverManager.logs.map(LogEntry.parse)
        }
        // 日志详情 sheet
        .sheet(item: $selectedLog) { entry in
            LogDetailView(entry: entry)
        }
        // 导入引导 sheet
        .sheet(item: $importTarget) { target in
            ImportGuideView(target: target, mcpURL: importingURL.isEmpty ? mcpURL : importingURL) {
                importTarget = nil
                importingURL = ""
            }
        }
        // 导入结果 toast
        .overlay(alignment: .bottom) {
            if let msg = importToast {
                Text(msg)
                    .font(.callout)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { importToast = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: importToast)
    }

    // MARK: - Sub-views

    private var portConfigBar: some View {
        HStack(spacing: 12) {
            Text("MCP 端口")
                .font(.caption).foregroundColor(.secondary)
            TextField("端口", value: $appConfig.mcpConfig.port, formatter: NumberFormatter())
                .textFieldStyle(.roundedBorder).frame(width: 80)
            Text("启动后监听: \(mcpURL)")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MCP 服务").font(.headline)
                HStack(spacing: 4) {
                    Circle()
                        .fill(serverManager.isRunning ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(serverManager.isRunning ? "运行中" : "已停止")
                        .font(.caption).foregroundColor(.secondary)
                    if serverManager.isRunning {
                        Text("·  \(mcpURL)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button(action: toggleServer) {
                Text(serverManager.isRunning ? "停止" : "启动")
            }
            .buttonStyle(.borderedProminent)
            .tint(serverManager.isRunning ? .red : .blue)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // 每个服务器独立 MCP 入口列表
    private var importBar: some View {
        VStack(spacing: 0) {
            // 表头
            HStack {
                Text("MCP 入口").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                Spacer()
                Text("工具数").font(.caption).foregroundColor(.secondary).frame(width: 48, alignment: .center)
                Text("操作").font(.caption).foregroundColor(.secondary).frame(width: 160, alignment: .center)
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 全量入口
            MCPEndpointRow(
                label: "全部工具",
                icon: "list.bullet",
                url: mcpURL,
                toolCount: totalToolCount,
                onImport: { target in
                    importingURL = mcpURL
                    if target == .cursor || target == .claudeDesktop {
                        tryAutoImport(target: target, url: mcpURL, key: "mcp-aha-All")
                    } else {
                        importTarget = target
                    }
                },
                onCopy: {
                    copyToClipboard(mcpURL, toast: "✓ 已复制全量入口地址")
                }
            )

            // 每个服务器配置的独立入口
            ForEach(serverProfileStore.profiles) { profile in
                let url  = "http://127.0.0.1:\(appConfig.mcpConfig.port)\(profile.mcpPath)"
                let cnt  = endpointStore.endpoints.filter { $0.serverID == profile.id && $0.isEnabled }.count
                Divider().padding(.leading, 12)
                MCPEndpointRow(
                    label: profile.name,
                    icon: "server.rack",
                    url: url,
                    toolCount: cnt,
                    onImport: { target in
                        importingURL = url
                        if target == .cursor || target == .claudeDesktop {
                            let key = "mcp-aha-\(profile.name)"
                            tryAutoImport(target: target, url: url, key: key)
                        } else {
                            importTarget = target
                        }
                    },
                    onCopy: {
                        copyToClipboard(url, toast: "✓ 已复制 \(profile.name) 入口地址")
                    }
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var testPanel: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("测试请求:").font(.caption).foregroundColor(.secondary)
                TextField("JSON-RPC", text: $testRequest, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 60, maxHeight: 80)
            }
            Button(action: sendTestRequest) {
                if isTesting { ProgressView().scaleEffect(0.8) }
                else { Text("发送") }
            }
            .disabled(isTesting).buttonStyle(.borderedProminent)
            VStack(alignment: .leading, spacing: 4) {
                Text("响应:").font(.caption).foregroundColor(.secondary)
                Text(testResponse.isEmpty ? "等待响应…" : testResponse)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(testResponse.isEmpty ? .secondary : .primary)
                    .frame(minHeight: 60, maxHeight: 80).lineLimit(4)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var logArea: some View {
        VStack(spacing: 0) {
            // 分页工具栏
            HStack(spacing: 8) {
                Text("日志")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                Text("共 \(logs.count) 条")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("第 \(currentPage + 1) / \(totalPages) 页")
                    .font(.caption).foregroundColor(.secondary)
                Button { currentPage = max(0, currentPage - 1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain).disabled(currentPage == 0)
                Button { currentPage = min(totalPages - 1, currentPage + 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain).disabled(currentPage >= totalPages - 1)
                Button {
                    logs.removeAll()
                    serverManager.logs.removeAll()
                    currentPage = 0
                } label: {
                    Image(systemName: "trash").foregroundColor(.secondary)
                }
                .buttonStyle(.plain).help("清空日志")
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 日志列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(pagedLogs) { entry in
                        LogRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedLog = entry }
                        Divider().padding(.leading, 32)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        // 新日志到来时跳到第 0 页（最新）
        .onChange(of: serverManager.logs.count) { _ in
            let newEntries = serverManager.logs.map(LogEntry.parse)
            logs = newEntries
            currentPage = 0
        }
    }

    // MARK: - Auto import helpers

    private func tryAutoImport(target: ImportTarget, url: String, key: String) {
        let configEntry: [String: Any] = ["url": url]

        let filePath: String
        switch target {
        case .cursor:
            filePath = (NSHomeDirectory() as NSString).appendingPathComponent(".cursor/mcp.json")
        case .claudeDesktop:
            filePath = (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        default:
            importingURL = url
            importTarget = target
            return
        }

        do {
            let fileURL = URL(fileURLWithPath: filePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var config: [String: Any] = [:]
            if let data = try? Data(contentsOf: fileURL),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                config = existing
            }

            var servers = config["mcpServers"] as? [String: Any] ?? [:]
            servers[key] = configEntry
            config["mcpServers"] = servers

            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)

            withAnimation { importToast = "✓ 已写入 \(target.title) 配置，重启工具后生效" }
        } catch {
            importingURL = url
            importTarget = target   // 写入失败，降级到引导 sheet
        }
    }

    private func copyToClipboard(_ text: String, toast: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { importToast = toast }
    }

    // MARK: - Actions

    private func toggleServer() {
        if serverManager.isRunning {
            serverManager.stop()
            let entry = LogEntry.parse("[\(isoNow())] 服务已停止")
            logs.append(entry)
        } else {
            do {
                try serverManager.start(mcpConfig: appConfig.mcpConfig)
                let entry = LogEntry.parse("[\(isoNow())] 服务已启动: \(mcpURL)")
                logs.append(entry)
                currentPage = 0
            } catch {
                let entry = LogEntry.parse("[\(isoNow())] 启动失败: \(error.localizedDescription)")
                logs.append(entry)
            }
        }
    }

    private func sendTestRequest() {
        guard let url = URL(string: mcpURL) else { testResponse = "Invalid URL"; return }
        isTesting = true; testResponse = ""
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = testRequest.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                isTesting = false
                testResponse = error.map { "Error: \($0.localizedDescription)" }
                    ?? data.flatMap { String(data: $0, encoding: .utf8) }
                    ?? "No response"
            }
        }.resume()
    }

    private func isoNow() -> String { ISO8601DateFormatter().string(from: Date()) }
}

// MARK: - Import button

private struct ImportButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon).font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - MCP Endpoint Row

private struct MCPEndpointRow: View {
    let label: String
    let icon: String
    let url: String
    let toolCount: Int
    let onImport: (ImportTarget) -> Void
    let onCopy: () -> Void

    @State private var expanded = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).fontWeight(.medium)
                Text(url)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(toolCount) 个工具")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 52, alignment: .center)

            // 操作按钮
            HStack(spacing: 4) {
                Button { onCopy() } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered).controlSize(.mini)
                .help("复制 MCP 地址")

                Menu {
                    Button("导入 Cursor") { onImport(.cursor) }
                    Button("导入 Claude Desktop") { onImport(.claudeDesktop) }
                    Button("Claude Code 说明") { onImport(.claudeCode) }
                    Button("其他工具说明") { onImport(.generic) }
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                        .font(.caption2)
                }
                .menuStyle(.borderedButton)
                .controlSize(.mini)
            }
            .frame(width: 110)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Log row

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: levelIcon)
                .foregroundColor(levelColor)
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.body)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                if !entry.timestamp.isEmpty {
                    Text(entry.timestamp)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var levelIcon: String {
        switch entry.level {
        case .error:   return "xmark.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .request: return "arrow.down.circle.fill"
        case .info:    return "info.circle"
        }
    }
    private var levelColor: Color {
        switch entry.level {
        case .error:   return .red
        case .success: return .green
        case .request: return .blue
        case .info:    return .secondary
        }
    }
}

// MARK: - Log detail sheet

struct LogDetailView: View {
    let entry: LogEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("日志详情").font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            if !entry.timestamp.isEmpty {
                HStack {
                    Image(systemName: "clock").foregroundColor(.secondary)
                    Text(entry.timestamp).font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal).padding(.top, 10)
            }

            ScrollView {
                Text(entry.body)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(minWidth: 520, minHeight: 320)
    }
}

// MARK: - Import guide sheet

struct ImportGuideView: View {
    let target: ImportTarget
    let mcpURL: String
    let onDismiss: () -> Void

    private var configJSON: String {
        """
{
  "mcpServers": {
    "mcp-aha": {
      "url": "\(mcpURL)"
    }
  }
}
"""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("导入到 \(target.title)", systemImage: target.icon)
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch target {
                    case .claudeCode:
                        claudeCodeGuide
                    case .generic:
                        genericGuide
                    default:
                        manualFileGuide
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var claudeCodeGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("方式一：使用 CLI 命令（推荐）")
                .font(.headline)
            Text("在终端执行以下命令，将 mcp-aha 添加为 MCP 服务器：")
                .foregroundColor(.secondary)
            CodeSnippet(code: "claude mcp add --transport http --url \(mcpURL) mcp-aha")

            Divider()

            Text("方式二：手动编辑配置文件")
                .font(.headline)
            Text("编辑 `~/.claude/claude_desktop_config.json`，加入以下内容：")
                .foregroundColor(.secondary)
            CodeSnippet(code: configJSON)
        }
    }

    private var genericGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("通用接入方式")
                .font(.headline)
            Text("MCP 服务地址：")
                .foregroundColor(.secondary)
            CodeSnippet(code: mcpURL)

            Text("标准配置格式（JSON）：")
                .foregroundColor(.secondary)
            CodeSnippet(code: configJSON)

            Text("大多数支持 MCP 的工具都可以通过以上地址或 JSON 配置接入，具体步骤请参考对应工具的文档。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var manualFileGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("自动写入失败，请手动配置")
                .font(.headline)
            Text("请将以下内容合并到对应的配置文件中：")
                .foregroundColor(.secondary)
            CodeSnippet(code: configJSON)
            Group {
                switch target {
                case .cursor:
                    Text("文件路径：`~/.cursor/mcp.json`").font(.caption).foregroundColor(.secondary)
                case .claudeDesktop:
                    Text("文件路径：`~/Library/Application Support/Claude/claude_desktop_config.json`")
                        .font(.caption).foregroundColor(.secondary)
                default:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Code snippet block

private struct CodeSnippet: View {
    let code: String
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }
}
