import SwiftUI

// MARK: - Navigation selection

enum NavItem: Hashable {
    case config
    case allAPIs
    case ungrouped
    case group(UUID)
    case server
    case importExport
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var appConfig     = AppConfig.shared
    @StateObject private var endpointStore = EndpointStore.shared
    @StateObject private var groupStore    = GroupStore.shared

    @State private var selectedNav: NavItem = .allAPIs

    // 新建分组
    @State private var isAddingGroup = false
    @State private var newGroupName  = ""

    // 重命名分组
    @State private var renamingGroup: APIGroup? = nil
    @State private var renameText = ""


    var body: some View {
        NavigationSplitView {
            // ── 直接把 List 放在 sidebar 闭包里，避免 Binding 回传失效 ──
            List(selection: $selectedNav) {

                Section("服务器配置") {
                    Label("服务器配置", systemImage: "gearshape")
                        .tag(NavItem.config)
                }

                Section {
                    Label("全部", systemImage: "list.bullet")
                        .badge(endpointStore.endpoints.count)
                        .tag(NavItem.allAPIs)
                        .contextMenu {
                            Button("清空所有 API", role: .destructive) {
                                clearAllAPIs()
                            }
                            .disabled(endpointStore.endpoints.isEmpty)
                        }

                    ForEach(groupStore.groups) { group in
                        let cnt = endpointStore.endpoints.filter { $0.groupID == group.id }.count
                        Label(group.name, systemImage: "folder")
                            .badge(cnt)
                            .tag(NavItem.group(group.id))
                            .contextMenu {
                                Button("重命名") {
                                    renameText   = group.name
                                    renamingGroup = group
                                }
                                Divider()
                                Button("清空分组内 API", role: .destructive) {
                                    clearGroupAPIs(group)
                                }
                                Button("删除分组", role: .destructive) {
                                    deleteGroup(group)
                                }
                            }
                    }

                    // 新建分组输入行
                    if isAddingGroup {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.secondary)
                            TextField("分组名称", text: $newGroupName)
                                .textFieldStyle(.plain)
                                .onSubmit { commitNewGroup() }
                                .onExitCommand { cancelAddGroup() }
                        }
                    }

                } header: {
                    HStack {
                        Text("API 分组")
                        Spacer()
                        Button {
                            isAddingGroup = true
                            newGroupName  = ""
                        } label: {
                            Image(systemName: "plus").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("新建分组")
                    }
                }

                Section("系统配置") {
                    Label("服务", systemImage: "server.rack")
                        .tag(NavItem.server)

                    Label("导入 / 导出", systemImage: "arrow.up.arrow.down")
                        .tag(NavItem.importExport)
                }

            }
            .listStyle(.sidebar)
            .frame(minWidth: 150)

        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        // 分组被删除时退回全部列表
        .onChange(of: groupStore.groups) { groups in
            if case .group(let id) = selectedNav,
               !groups.contains(where: { $0.id == id }) {
                selectedNav = .allAPIs
            }
        }
        // 重命名 Alert
        .alert("重命名分组", isPresented: Binding(
            get: { renamingGroup != nil },
            set: { if !$0 { renamingGroup = nil } }
        )) {
            TextField("分组名称", text: $renameText)
            Button("确定") { commitRename() }
            Button("取消", role: .cancel) { renamingGroup = nil }
        } message: {
            if let g = renamingGroup { Text("当前名称：\(g.name)") }
        }
    }

    // MARK: - Detail view

    @ViewBuilder
    private var detailView: some View {
        switch selectedNav {
        case .config:
            ConfigView()
        case .allAPIs:
            APIListView(filter: .all)
        case .ungrouped:
            APIListView(filter: .ungrouped)
        case .group(let id):
            if let group = groupStore.groups.first(where: { $0.id == id }) {
                APIListView(filter: .group(id))
                    .id(group.id)
            } else {
                APIListView(filter: .all)
            }
        case .server:
            ServerView()
        case .importExport:
            ImportExportView()
        }
    }

    // MARK: - Group actions

    private func commitNewGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { cancelAddGroup(); return }
        let group = APIGroup(name: name)
        groupStore.add(group)
        selectedNav   = .group(group.id)
        isAddingGroup = false
        newGroupName  = ""
    }

    private func cancelAddGroup() {
        isAddingGroup = false
        newGroupName  = ""
    }

    private func commitRename() {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, var group = renamingGroup else { renamingGroup = nil; return }
        group.name = name
        groupStore.update(group)
        renamingGroup = nil
    }

    private func deleteGroup(_ group: APIGroup) {
        endpointStore.clearGroup(group.id)
        if case .group(let id) = selectedNav, id == group.id {
            selectedNav = .allAPIs
        }
        groupStore.delete(group)
    }

    private func clearGroupAPIs(_ group: APIGroup) {
        endpointStore.deleteAllInGroup(group.id)
    }

    private func clearAllAPIs() {
        endpointStore.deleteAll()
    }
}
