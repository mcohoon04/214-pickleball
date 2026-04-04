import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var avatarUrl: String?
    var timezone: String
    var pushEnabled: Bool
    var emailEnabled: Bool
    var apnsDeviceToken: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case timezone
        case pushEnabled = "push_enabled"
        case emailEnabled = "email_enabled"
        case apnsDeviceToken = "apns_device_token"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PlayerInfo: Codable, Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}
