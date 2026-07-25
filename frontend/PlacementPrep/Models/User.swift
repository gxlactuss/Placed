import Foundation

struct User: Codable, Identifiable {
    let id: Int
    let email: String
    let fullName: String?
    let targetRole: String?
    let isVerified: Bool
    let onboarded: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, onboarded
        case fullName = "full_name"
        case targetRole = "target_role"
        case isVerified = "is_verified"
        case createdAt = "created_at"
    }
}

/// Body for `POST /api/auth/verify`.
struct VerifyCodeRequest: Codable {
    let code: String
}

/// Partial profile update for `PATCH /api/auth/me`. Nil fields are omitted by
/// the synthesized encoder, so only what's set is sent.
struct UserUpdate: Codable {
    var fullName: String?
    var targetRole: String?
    var onboarded: Bool?

    enum CodingKeys: String, CodingKey {
        case onboarded
        case fullName = "full_name"
        case targetRole = "target_role"
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case user
    }
}

struct SignupRequest: Codable {
    let email: String
    let password: String
    let fullName: String?
    let targetRole: String?

    enum CodingKeys: String, CodingKey {
        case email, password
        case fullName = "full_name"
        case targetRole = "target_role"
    }
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}
