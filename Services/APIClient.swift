import Foundation
import os

private let logger = Logger(subsystem: "com.pineapplestack.tv", category: "API")

actor APIClient {
    static let shared = APIClient()

    private var baseURL: String = ""
    private var accessToken: String?
    private var refreshToken: String?
    private var isRefreshing = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    private init() {}

    // MARK: - Configuration

    func configure(baseURL: String, accessToken: String?, refreshToken: String?) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func updateTokens(access: String, refresh: String) {
        self.accessToken = access
        self.refreshToken = refresh
    }

    func clearTokens() {
        self.accessToken = nil
        self.refreshToken = nil
    }

    var isAuthenticated: Bool {
        accessToken != nil
    }

    var currentAccessToken: String? {
        accessToken
    }

    var serverBaseURL: String {
        baseURL
    }

    // MARK: - Authentication

    func login(username: String, password: String) async throws -> AuthTokenResponse {
        let body = LoginRequest(username: username, password: password)
        let response: AuthTokenResponse = try await post(
            path: "/api/accounts/token/",
            body: body,
            authenticated: false
        )
        self.accessToken = response.access
        self.refreshToken = response.refresh
        return response
    }

    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else {
            throw APIError.notAuthenticated
        }

        isRefreshing = true
        defer { isRefreshing = false }

        struct RefreshBody: Codable { let refresh: String }
        let body = RefreshBody(refresh: refresh)

        let request = try buildRequest(
            path: "/api/accounts/token/refresh/",
            method: "POST",
            body: try encoder.encode(body),
            authenticated: false
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            self.accessToken = nil
            self.refreshToken = nil
            throw APIError.notAuthenticated
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        let tokenResponse = try decoder.decode(TokenRefreshResponse.self, from: data)
        self.accessToken = tokenResponse.access

        try await KeychainService.shared.save(tokenResponse.access, forKey: Constants.keychainAccessToken)
    }

    // MARK: - HTTP Methods

    func get<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let request = try buildRequest(path: path, method: "GET", queryItems: queryItems)
        return try await execute(request)
    }

    func post<T: Decodable, B: Encodable>(path: String, body: B, authenticated: Bool = true) async throws -> T {
        let bodyData = try encoder.encode(body)
        let request = try buildRequest(path: path, method: "POST", body: bodyData, authenticated: authenticated)
        return try await execute(request)
    }

    func postNoResponse<B: Encodable>(path: String, body: B) async throws {
        let bodyData = try encoder.encode(body)
        let request = try buildRequest(path: path, method: "POST", body: bodyData)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let httpResponse = response as? HTTPURLResponse {
                throw APIError.httpError(httpResponse.statusCode)
            }
            throw APIError.invalidResponse
        }
    }

    func delete(path: String) async throws {
        let request = try buildRequest(path: path, method: "DELETE")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let httpResponse = response as? HTTPURLResponse {
                throw APIError.httpError(httpResponse.statusCode)
            }
            throw APIError.invalidResponse
        }
    }

    // MARK: - URL Building

    func buildStreamURL(channelId: Int) -> URL? {
        URL(string: "\(baseURL)/proxy/hls/stream/\(channelId)")
    }

    func buildTSStreamURL(channelUUID: String) -> URL? {
        URL(string: "\(baseURL)/proxy/ts/stream/\(channelUUID)")
    }

    func buildRecordingFileURL(recordingId: Int) -> URL? {
        URL(string: "\(baseURL)/api/channels/recordings/\(recordingId)/file/")
    }

    func buildLogoURL(logoPath: String) -> URL? {
        if logoPath.hasPrefix("http") {
            return URL(string: logoPath)
        }
        return URL(string: "\(baseURL)\(logoPath)")
    }

    func authHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        if let token = accessToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    // MARK: - Private Helpers

    private func buildRequest(
        path: String,
        method: String,
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil,
        authenticated: Bool = true
    ) throws -> URLRequest {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL(path)
        }

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if authenticated, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest, retried: Bool = false) async throws -> T {
        logger.info("\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        logger.info("Response: \(httpResponse.statusCode), \(data.count) bytes")

        // If 401, try refreshing the token once
        if httpResponse.statusCode == 401, !retried, !isRefreshing {
            try await refreshAccessToken()
            // Rebuild request with new token
            var newRequest = request
            if let token = accessToken {
                newRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return try await execute(newRequest, retried: true)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "binary"
            logger.error("Decode error for \(String(describing: T.self)): \(error)\nPreview: \(preview)")
            throw APIError.decodingError(error)
        }
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)
    case notAuthenticated
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Invalid URL: \(path)"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "Server error (\(code))"
        case .notAuthenticated:
            return "Not authenticated. Please log in again."
        case .decodingError(let error):
            return "Data error: \(error.localizedDescription)"
        }
    }
}
