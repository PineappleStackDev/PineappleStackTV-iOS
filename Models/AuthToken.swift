import Foundation

struct AuthTokenResponse: Codable {
    let access: String
    let refresh: String
}

struct TokenRefreshResponse: Codable {
    let access: String
}

struct LoginRequest: Codable {
    let username: String
    let password: String
}
