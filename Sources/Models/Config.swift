import Foundation

struct MCPConfig: Codable, Equatable {
    var port: Int

    static let `default` = MCPConfig(port: 3000)
}

@MainActor
class AppConfig: ObservableObject {
    static let shared = AppConfig()

    @Published var mcpConfig: MCPConfig {
        didSet { save() }
    }

    var serverURL: String { "127.0.0.1" }

    private let mcpConfigKey = "mcp_config"

    private init() {
        if let data = UserDefaults.standard.data(forKey: mcpConfigKey),
           let config = try? JSONDecoder().decode(MCPConfig.self, from: data) {
            self.mcpConfig = config
        } else {
            self.mcpConfig = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(mcpConfig) {
            UserDefaults.standard.set(data, forKey: mcpConfigKey)
        }
    }
}
