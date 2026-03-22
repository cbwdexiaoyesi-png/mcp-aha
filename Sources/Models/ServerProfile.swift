import Foundation

// MARK: - Auth mode

enum AuthMode: String, Codable, CaseIterable {
    case none              = "none"
    case clientCredentials = "clientCredentials"

    var displayName: String {
        switch self {
        case .none:              return "无"
        case .clientCredentials: return "客户端凭证模式"
        }
    }
}

// MARK: - ServerProfile

struct ServerProfile: Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var baseURL: String
    var headers: String   // JSON object, e.g. {"Authorization":"Bearer xxx"}

    // 前置鉴权
    var authMode:   AuthMode = .none
    var authURL:    String   = ""
    var authBody:   String   = "{}"
    var authExpiry: Int      = 120   // 分钟

    init(id: UUID = UUID(), name: String, baseURL: String = "", headers: String = defaultHeaders,
         authMode: AuthMode = .none, authURL: String = "", authBody: String = "{}", authExpiry: Int = 120) {
        self.id        = id
        self.name      = name
        self.baseURL   = baseURL
        self.headers   = headers
        self.authMode  = authMode
        self.authURL   = authURL
        self.authBody  = authBody
        self.authExpiry = authExpiry
    }

    var isValid: Bool { !baseURL.isEmpty }

    /// 该服务器对应的 MCP 路径，格式 /{slug}/mcp
    /// 中文名自动转拼音，如"纷享销客" → /fen-xiang-xiao-ke/mcp
    var mcpPath: String {
        // 用系统 CFStringTransform 将中文转拼音（去声调）
        let mutable = NSMutableString(string: name)
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        var slug = (mutable as String)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        // 合并连续短横线并去除首尾短横线
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = String(id.uuidString.prefix(8)) }
        return "/\(slug)/mcp"
    }

    /// Parse headers JSON → [String: String]; returns empty dict on invalid JSON
    var parsedHeaders: [String: String] {
        guard let data = headers.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj.compactMapValues { "\($0)" }
    }

    var isHeadersValid: Bool {
        guard let data = headers.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    static let defaultHeaders = """
{
  "Authorization": "Bearer your-token-here"
}
"""
}

// MARK: - Codable（兼容旧数据中的 accessToken 字段）

extension ServerProfile: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, headers, accessToken
        case authMode, authURL, authBody, authExpiry
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = try c.decode(UUID.self,   forKey: .id)
        name    = try c.decode(String.self, forKey: .name)
        baseURL = try c.decode(String.self, forKey: .baseURL)

        if let h = try c.decodeIfPresent(String.self, forKey: .headers) {
            headers = h
        } else if let token = try c.decodeIfPresent(String.self, forKey: .accessToken),
                  !token.isEmpty {
            headers = "{\n  \"Authorization\": \"Bearer \(token)\"\n}"
        } else {
            headers = ServerProfile.defaultHeaders
        }

        authMode   = (try? c.decodeIfPresent(AuthMode.self, forKey: .authMode))   ?? .none
        authURL    = (try? c.decodeIfPresent(String.self,   forKey: .authURL))    ?? ""
        authBody   = (try? c.decodeIfPresent(String.self,   forKey: .authBody))   ?? "{}"
        authExpiry = (try? c.decodeIfPresent(Int.self,      forKey: .authExpiry)) ?? 120
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,         forKey: .id)
        try c.encode(name,       forKey: .name)
        try c.encode(baseURL,    forKey: .baseURL)
        try c.encode(headers,    forKey: .headers)
        try c.encode(authMode,   forKey: .authMode)
        try c.encode(authURL,    forKey: .authURL)
        try c.encode(authBody,   forKey: .authBody)
        try c.encode(authExpiry, forKey: .authExpiry)
    }
}

// MARK: - Store

@MainActor
class ServerProfileStore: ObservableObject {
    static let shared = ServerProfileStore()

    @Published var profiles: [ServerProfile] {
        didSet { save() }
    }

    private let key = "server_profiles"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            self.profiles = saved
        } else if let old = UserDefaults.standard.data(forKey: "server_config"),
                  let oldCfg = try? JSONDecoder().decode(LegacyServerConfig.self, from: old),
                  !oldCfg.baseURL.isEmpty {
            // 迁移最旧格式（server_config key）
            let h = oldCfg.accessToken.isEmpty
                ? ServerProfile.defaultHeaders
                : "{\n  \"Authorization\": \"Bearer \(oldCfg.accessToken)\"\n}"
            self.profiles = [ServerProfile(name: "默认服务器", baseURL: oldCfg.baseURL, headers: h)]
        } else {
            self.profiles = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(_ profile: ServerProfile)    { profiles.append(profile) }
    func delete(_ profile: ServerProfile) { profiles.removeAll { $0.id == profile.id } }
    func update(_ profile: ServerProfile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
        }
    }
}

private struct LegacyServerConfig: Codable {
    var baseURL: String
    var accessToken: String
}
