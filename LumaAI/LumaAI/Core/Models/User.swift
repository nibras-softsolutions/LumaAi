import Foundation

public struct User: Codable, Identifiable, Equatable {
    public let id: String
    public var fullName: String
    public var email: String
    public var profileImageUrl: String?
    public var customName: String?
    public var bio: String?
    public var avatarEmoji: String?
    public var avatarColorHex: String?

    public init(
        id: String,
        fullName: String,
        email: String,
        profileImageUrl: String? = nil,
        customName: String? = nil,
        bio: String? = nil,
        avatarEmoji: String? = nil,
        avatarColorHex: String? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.email = email
        self.profileImageUrl = profileImageUrl
        self.customName = customName
        self.bio = bio
        self.avatarEmoji = avatarEmoji
        self.avatarColorHex = avatarColorHex
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
        case profileImageUrl = "profile_image_url"
        case customName = "custom_name"
        case bio
        case avatarEmoji = "avatar_emoji"
        case avatarColorHex = "avatar_color_hex"
    }
}

public struct LoginRequest: Codable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct RegisterRequest: Codable {
    public let fullName: String
    public let email: String
    public let password: String

    public init(fullName: String, email: String, password: String) {
        self.fullName = fullName
        self.email = email
        self.password = password
    }

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case email
        case password
    }
}
