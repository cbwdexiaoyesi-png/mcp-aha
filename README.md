# mcp-aha

**Language / 语言:** **English** (default) · [简体中文](#chinese)

---

<a id="english"></a>

## English

**mcp-aha** is a native **macOS** app that turns arbitrary **REST APIs** into **MCP (Model Context Protocol)** tools so assistants (Claude, Cursor, and others) can call your backends directly.

### Features

- **Visual API management** — add, edit, delete endpoints; organize with groups  
- **Multiple server profiles** — per-server base URL and auth  
- **Flexible auth** — static token or client-credentials flow with auto refresh  
- **JavaScript transforms** — JavaScriptCore runs request/response mapping scripts  
- **MCP protocol** — JSON-RPC, including `tools`, `resources`, `prompts`, etc.  
- **One-click import** — Cursor, Claude Desktop, Claude Code  
- **Import / export** — full configuration as JSON  

### Download

Installable **macOS** builds (`.dmg`) are on **[Releases](./releases)**. Open the DMG, drag **mcp-aha** into **Applications**.  
Requires **macOS 13+**. Pre-built DMGs are currently **Apple Silicon (arm64)**; Intel users can build from source with Xcode.

### Project layout

```
mcp-aha/
├── project.yml              # XcodeGen spec
├── Resources/
│   ├── Info.plist
│   ├── mcp-aha.entitlements
│   └── Assets.xcassets/
└── Sources/
    ├── App/McpAhaApp.swift
    ├── Models/              # Config, ServerProfile, APIEndpoint, APIGroup
    ├── Views/               # SwiftUI screens
    └── Services/            # MCPServer, JSEngine, APIGateway
```

### Requirements

- macOS 13.0+  
- Xcode 15.0+  
- Swift 5.9+  
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (optional, to generate the Xcode project)  

### Build

```bash
brew install xcodegen   # if needed
cd mcp-aha
xcodegen generate
```

Open the generated `mcp-aha.xcodeproj`, select the **mcp-aha** scheme, run (⌘R).

Command line:

```bash
xcodegen generate
xcodebuild -project mcp-aha.xcodeproj -scheme mcp-aha -configuration Debug build
```

Build products go under Xcode’s DerivedData (not committed).

To produce a **Release DMG** locally (output under `release/`):

```bash
./scripts/package-dmg.sh
```

### Usage (short)

1. **Servers** — add a profile: name, base URL, headers (e.g. `Authorization`). Use client-credentials mode if tokens must be fetched automatically; `${AUTH_RESPONSE.xxx}` is supported in templates.  
2. **APIs** — define name, description, path (`{param}` supported), method, server, and input JSON Schema.  
3. **Transforms** — optional JS for request (`_path` / `_query` / `_body`) and response shaping.  
4. **Service** — pick a port (default `3000`), start the MCP HTTP server.  
5. **Connect** — use **Import** for Cursor / Claude Desktop, or configure your client with the shown MCP URL.  

Example client snippet:

```json
{
  "mcpServers": {
    "mcp-aha": {
      "url": "http://127.0.0.1:3000/mcp"
    }
  }
}
```

Claude Code example:

```bash
claude mcp add --transport http --url http://127.0.0.1:3000/mcp mcp-aha
```

### MCP routes

- `/mcp` — all enabled tools  
- `/{server-slug}/mcp` — tools for one server only  

Slugs are derived from the server display name (e.g. pinyin for CJK names).

### Security note

Transform scripts run **locally** in JavaScriptCore with your app’s privileges. Only load configs and scripts you trust.

### Technical notes

- MCP revision: **2024-11-05**  
- Transport: **HTTP POST**, JSON-RPC 2.0  
- Persistence: **UserDefaults**  

### License

MIT — see [LICENSE](LICENSE).

---

<a id="chinese"></a>

## 简体中文

**mcp-aha** 是一款原生 **macOS** 桌面应用：把任意 **REST API** 封装为 **MCP（Model Context Protocol）** 工具，供 Claude、Cursor 等 AI 助手直接调用后端。

### 功能特性

- **可视化 API 管理**：增删改端点，支持分组  
- **多服务器配置**：每个服务器独立的 Base URL 与认证  
- **灵活认证**：静态 Token 或客户端凭证模式（自动获取/刷新 Token）  
- **JavaScript 转换**：使用 JavaScriptCore 执行请求/响应脚本  
- **MCP 协议**：完整 JSON-RPC（tools、resources、prompts 等）  
- **一键导入**：Cursor、Claude Desktop、Claude Code  
- **导入/导出**：JSON 全量配置  

### 下载安装

在 **[Releases](./releases)** 下载 **macOS** 安装包（`.dmg`），打开后把 **mcp-aha** 拖入「应用程序」。  
需要 **macOS 13+**。当前预编译包为 **Apple Silicon (arm64)**；Intel 设备可用 Xcode 从源码编译。

### 项目结构

```
mcp-aha/
├── project.yml              # XcodeGen 配置
├── Resources/
│   ├── Info.plist
│   ├── mcp-aha.entitlements
│   └── Assets.xcassets/
└── Sources/
    ├── App/McpAhaApp.swift
    ├── Models/
    ├── Views/
    └── Services/
```

### 环境要求

- macOS 13.0+  
- Xcode 15.0+  
- Swift 5.9+  
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（可选）  

### 本地开发

```bash
brew install xcodegen
cd mcp-aha
xcodegen generate
```

用 Xcode 打开 `mcp-aha.xcodeproj`，选择 **mcp-aha** scheme，运行 (⌘R)。

命令行编译：

```bash
xcodegen generate
xcodebuild -project mcp-aha.xcodeproj -scheme mcp-aha -configuration Debug build
```

打包 **Release DMG**（生成到 `release/` 目录）：

```bash
./scripts/package-dmg.sh
```

### 使用说明（摘要）

1. **服务器**：名称、Base URL、请求头；客户端凭证模式支持 `${AUTH_RESPONSE.xxx}`。  
2. **API**：名称、描述、路径（支持 `{param}`）、方法、服务器、输入 JSON Schema。  
3. **转换脚本**：请求（`_path` / `_query` / `_body`）与响应可选 JS。  
4. **服务**：端口（默认 3000），启动 MCP HTTP 服务。  
5. **接入 AI**：使用「导入」或按各客户端文档配置 MCP URL。  

### MCP 路由

- `/mcp`：全部已启用 API  
- `/{server-slug}/mcp`：仅该服务器下的 API  

服务器 slug 由显示名称自动生成（中文名会转拼音等），例如名称「销售接口」可能对应 `/xiao-shou-jie-kou/mcp`。

### 安全说明

转换脚本在本地 **JavaScriptCore** 中以应用权限执行，请只使用可信的配置与脚本。

### 技术细节

- 协议版本：MCP 2024-11-05  
- 传输：HTTP POST（JSON-RPC 2.0）  
- 持久化：UserDefaults  

### 许可证

MIT，见 [LICENSE](LICENSE)。

**[↑ 回到顶部 / Back to top](#mcp-aha)** · **[English](#english)**
