import Foundation

struct APIEndpoint: Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var description: String
    var path: String
    var method: HTTPMethod
    var serverID: UUID?          // references ServerProfile.id
    var groupID: UUID?           // nil = ungrouped
    var inputSchema: String      // JSON Schema for MCP tool parameters
    var requestTransform: String
    var responseTransform: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        path: String,
        method: HTTPMethod = .GET,
        serverID: UUID? = nil,
        groupID: UUID? = nil,
        inputSchema: String = defaultInputSchema,
        requestTransform: String = defaultRequestTransform,
        responseTransform: String = defaultResponseTransform,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.path = path
        self.method = method
        self.serverID = serverID
        self.groupID = groupID
        self.inputSchema = inputSchema
        self.requestTransform = requestTransform
        self.responseTransform = responseTransform
        self.isEnabled = isEnabled
    }

    /// Parse inputSchema JSON string into a dictionary; falls back to empty object schema.
    var parsedInputSchema: [String: Any] {
        guard let data = inputSchema.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["type": "object", "properties": [:] as [String: Any]]
        }
        return obj
    }

    /// Returns true when inputSchema is valid JSON
    var isSchemaValid: Bool {
        guard let data = inputSchema.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    static let defaultInputSchema = """
{
  "type": "object",
  "properties": {
  },
  "required": []
}
"""

    static let defaultRequestTransform = """
function transform(params) {
    // params: MCP 传入的参数
    // 返回: 后端 API 需要的请求参数
    //
    // 支持三种参数位置:
    //   _path:  路径参数，替换 URL 中的 {key}
    //   _query: URL 查询参数
    //   _body:  请求体 (POST/PUT/PATCH)
    //
    // 示例:
    //   return {
    //     _path: { id: params.userId },
    //     _query: { page: params.page, size: 10 },
    //     _body: { name: params.name }
    //   };
    //
    // 如果不使用 _path/_query/_body，
    // 整个返回值将作为请求体发送（兼容 POST）
    return params;
}
"""

    static let defaultResponseTransform = """
function transform(response) {
    // response: 后端 API 返回的数据
    // 返回: MCP 返回的数据
    return response;
}
"""
}

// MARK: - Codable (custom to support defaults for new fields on old data)

extension APIEndpoint: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, description, path, method
        case serverID, groupID, inputSchema, requestTransform, responseTransform, isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,       forKey: .id)
        name             = try c.decode(String.self,     forKey: .name)
        path             = try c.decode(String.self,     forKey: .path)
        method           = try c.decode(HTTPMethod.self, forKey: .method)
        requestTransform = try c.decode(String.self,     forKey: .requestTransform)
        responseTransform = try c.decode(String.self,    forKey: .responseTransform)
        isEnabled        = try c.decode(Bool.self,       forKey: .isEnabled)
        description      = try c.decodeIfPresent(String.self, forKey: .description)  ?? ""
        inputSchema      = try c.decodeIfPresent(String.self, forKey: .inputSchema)  ?? APIEndpoint.defaultInputSchema
        serverID         = try c.decodeIfPresent(UUID.self,   forKey: .serverID)
        groupID          = try c.decodeIfPresent(UUID.self,   forKey: .groupID)
    }
}

enum HTTPMethod: String, Codable, CaseIterable {
    case GET
    case POST
    case PUT
    case DELETE
    case PATCH
}

@MainActor
class EndpointStore: ObservableObject {
    static let shared = EndpointStore()

    @Published var endpoints: [APIEndpoint] {
        didSet {
            save()
        }
    }

    private let endpointsKey = "api_endpoints"

    private init() {
        if let data = UserDefaults.standard.data(forKey: endpointsKey),
           let endpoints = try? JSONDecoder().decode([APIEndpoint].self, from: data) {
            self.endpoints = endpoints
        } else {
            self.endpoints = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(endpoints) {
            UserDefaults.standard.set(data, forKey: endpointsKey)
        }
    }

    func add(_ endpoint: APIEndpoint) {
        endpoints.append(endpoint)
    }

    func update(_ endpoint: APIEndpoint) {
        if let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) {
            endpoints[index] = endpoint
        }
    }

    func delete(_ endpoint: APIEndpoint) {
        endpoints.removeAll { $0.id == endpoint.id }
    }

    func move(from source: IndexSet, to destination: Int) {
        endpoints.move(fromOffsets: source, toOffset: destination)
    }

    /// 删除分组时，将该分组下的 API 归回"未分组"
    func clearGroup(_ groupID: UUID) {
        for i in endpoints.indices where endpoints[i].groupID == groupID {
            endpoints[i].groupID = nil
        }
    }

    /// 删除分组内的所有 API
    func deleteAllInGroup(_ groupID: UUID) {
        endpoints.removeAll { $0.groupID == groupID }
    }

    /// 删除所有 API
    func deleteAll() {
        endpoints.removeAll()
    }
}
