import SwiftUI
import UniformTypeIdentifiers

// MARK: - ImportExportView

struct ImportExportView: View {
    @StateObject private var serverStore   = ServerProfileStore.shared
    @StateObject private var endpointStore = EndpointStore.shared

    @State private var exportResult: String = ""
    @State private var importResult: String = ""
    @State private var jsonPreview: String = ""
    @State private var importText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 导出区域
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("将当前所有服务器配置及其关联的 API 导出为 JSON 文件。")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        DisclosureGroup("预览 JSON") {
                            ScrollView {
                                Text(jsonPreview)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 200)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(4)
                        }

                        HStack {
                            if !exportResult.isEmpty {
                                Text(exportResult)
                                    .font(.caption)
                                    .foregroundColor(exportResult.hasPrefix("✓") ? .green : .red)
                            }
                            Spacer()
                            Button {
                                copyToClipboard()
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                exportToFile()
                            } label: {
                                Label("导出到文件", systemImage: "doc.badge.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } label: {
                    HStack {
                        Label("导出配置", systemImage: "square.and.arrow.up")
                            .font(.headline)
                        Spacer()
                        Text("\(serverStore.profiles.count) 个服务器, \(endpointStore.endpoints.count) 个 API")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Divider()

                // 导入区域
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("从 JSON 文件或粘贴内容导入服务器配置及 API。同名服务器会自动重命名。")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("JSON 内容")
                            .font(.caption).foregroundColor(.secondary)

                        TextEditor(text: $importText)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(height: 150)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(4)

                        HStack {
                            if !importResult.isEmpty {
                                Text(importResult)
                                    .font(.caption)
                                    .foregroundColor(importResult.hasPrefix("✓") ? .green : .orange)
                                    .lineLimit(3)
                            }
                            Spacer()

                            Button {
                                importFromFile()
                            } label: {
                                Label("从文件导入", systemImage: "doc.badge.arrow.down")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                importFromText()
                            } label: {
                                Label("导入", systemImage: "square.and.arrow.down.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                } label: {
                    Label("导入配置", systemImage: "square.and.arrow.down")
                        .font(.headline)
                }
            }
            .padding()
        }
        .onAppear {
            jsonPreview = generateJSON()
        }
    }

    // MARK: - JSON Generation

    private func generateJSON() -> String {
        var exportData: [String: Any] = [:]
        var serversArray: [[String: Any]] = []

        for profile in serverStore.profiles {
            var serverDict: [String: Any] = [
                "name": profile.name,
                "baseURL": profile.baseURL,
                "headers": profile.headers,
                "authMode": profile.authMode.rawValue,
                "authURL": profile.authURL,
                "authBody": profile.authBody,
                "authExpiry": profile.authExpiry
            ]

            // 该服务器下的 API
            let apis = endpointStore.endpoints.filter { $0.serverID == profile.id }
            if !apis.isEmpty {
                serverDict["apis"] = apis.map { api -> [String: Any] in
                    [
                        "name": api.name,
                        "description": api.description,
                        "path": api.path,
                        "method": api.method.rawValue,
                        "isEnabled": api.isEnabled,
                        "inputSchema": api.inputSchema,
                        "requestTransform": api.requestTransform,
                        "responseTransform": api.responseTransform
                    ]
                }
            }

            serversArray.append(serverDict)
        }

        exportData["servers"] = serversArray

        // 未关联服务器的 API
        let orphanAPIs = endpointStore.endpoints.filter { $0.serverID == nil }
        if !orphanAPIs.isEmpty {
            exportData["orphan_apis"] = orphanAPIs.map { api -> [String: Any] in
                [
                    "name": api.name,
                    "description": api.description,
                    "path": api.path,
                    "method": api.method.rawValue,
                    "isEnabled": api.isEnabled,
                    "inputSchema": api.inputSchema,
                    "requestTransform": api.requestTransform,
                    "responseTransform": api.responseTransform
                ]
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    // MARK: - Export

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jsonPreview, forType: .string)
        exportResult = "✓ 已复制到剪贴板"
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "mcp-config-\(dateStamp()).json"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try jsonPreview.write(to: url, atomically: true, encoding: .utf8)
                exportResult = "✓ 已导出到 \(url.lastPathComponent)"
            } catch {
                exportResult = "✗ 导出失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Import

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                importText = try String(contentsOf: url, encoding: .utf8)
                importResult = "已加载文件，点击「导入」确认"
            } catch {
                importResult = "✗ 读取文件失败: \(error.localizedDescription)"
            }
        }
    }

    private func importFromText() {
        guard let data = importText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            importResult = "✗ JSON 格式错误"
            return
        }

        let result = parseAndImport(json: json)
        importResult = result
        jsonPreview = generateJSON()
    }

    private func parseAndImport(json: [String: Any]) -> String {
        guard let servers = json["servers"] as? [[String: Any]] else {
            return "✗ JSON 格式错误: 缺少 servers 数组"
        }

        var importedServers = 0
        var importedAPIs = 0
        var renamedServers: [String] = []

        for serverDict in servers {
            guard let name = serverDict["name"] as? String else { continue }

            // 检查名称冲突
            var finalName = name
            if serverStore.profiles.contains(where: { $0.name == name }) {
                finalName = generateUniqueName(base: name)
                renamedServers.append("\(name) → \(finalName)")
            }

            // 创建 ServerProfile
            let profile = ServerProfile(
                name: finalName,
                baseURL: serverDict["baseURL"] as? String ?? "",
                headers: serverDict["headers"] as? String ?? ServerProfile.defaultHeaders,
                authMode: AuthMode(rawValue: serverDict["authMode"] as? String ?? "none") ?? .none,
                authURL: serverDict["authURL"] as? String ?? "",
                authBody: serverDict["authBody"] as? String ?? "{}",
                authExpiry: serverDict["authExpiry"] as? Int ?? 120
            )

            serverStore.add(profile)
            importedServers += 1

            // 导入该服务器下的 API
            if let apis = serverDict["apis"] as? [[String: Any]] {
                for apiDict in apis {
                    let endpoint = APIEndpoint(
                        name: apiDict["name"] as? String ?? "未命名 API",
                        description: apiDict["description"] as? String ?? "",
                        path: apiDict["path"] as? String ?? "/",
                        method: HTTPMethod(rawValue: apiDict["method"] as? String ?? "GET") ?? .GET,
                        serverID: profile.id,
                        groupID: nil,
                        inputSchema: apiDict["inputSchema"] as? String ?? "{}",
                        requestTransform: apiDict["requestTransform"] as? String ?? "return input;",
                        responseTransform: apiDict["responseTransform"] as? String ?? "return input;",
                        isEnabled: apiDict["isEnabled"] as? Bool ?? true
                    )
                    endpointStore.add(endpoint)
                    importedAPIs += 1
                }
            }
        }

        // 导入未关联服务器的 API
        if let orphans = json["orphan_apis"] as? [[String: Any]] {
            for apiDict in orphans {
                let endpoint = APIEndpoint(
                    name: apiDict["name"] as? String ?? "未命名 API",
                    description: apiDict["description"] as? String ?? "",
                    path: apiDict["path"] as? String ?? "/",
                    method: HTTPMethod(rawValue: apiDict["method"] as? String ?? "GET") ?? .GET,
                    serverID: nil,
                    groupID: nil,
                    inputSchema: apiDict["inputSchema"] as? String ?? "{}",
                    requestTransform: apiDict["requestTransform"] as? String ?? "return input;",
                    responseTransform: apiDict["responseTransform"] as? String ?? "return input;",
                    isEnabled: apiDict["isEnabled"] as? Bool ?? true
                )
                endpointStore.add(endpoint)
                importedAPIs += 1
            }
        }

        var msg = "✓ 导入完成: \(importedServers) 个服务器, \(importedAPIs) 个 API"
        if !renamedServers.isEmpty {
            msg += "\n⚠ 重命名: " + renamedServers.joined(separator: ", ")
        }
        return msg
    }

    private func generateUniqueName(base: String) -> String {
        let stamp = dateStamp()
        var index = 1
        var candidate = "\(base)-\(stamp)"
        while serverStore.profiles.contains(where: { $0.name == candidate }) {
            index += 1
            candidate = "\(base)-\(stamp)-\(index)"
        }
        return candidate
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyMMdd"
        return f.string(from: Date())
    }
}
