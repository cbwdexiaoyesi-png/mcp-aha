import Foundation

class APIGateway {
    private let profile: ServerProfile
    private let session: URLSession

    init(profile: ServerProfile) {
        self.profile = profile
        self.session = URLSession.shared
    }

    func call(
        endpoint: APIEndpoint,
        params: [String: Any]
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(profile.baseURL)\(endpoint.path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in profile.parsedHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if !params.isEmpty {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidJSON
        }

        return json
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidJSON
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .invalidResponse:
            return "无效的响应"
        case .invalidJSON:
            return "无效的 JSON"
        case .httpError(let statusCode):
            return "HTTP 错误: \(statusCode)"
        }
    }
}
