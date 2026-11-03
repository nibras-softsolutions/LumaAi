import Foundation

public struct APIConfiguration {
    public static var defaultBaseURL: URL {
        URL(string: "https://lumaai-j0u3.onrender.com")!
    }

    public var baseURL: URL

    public init(baseURL: URL = APIConfiguration.defaultBaseURL) {
        self.baseURL = baseURL
    }
}

public enum APIEndpoint {
    case health
    case healthAI
    case register
    case login
    case googleAuth
    case me
    case logout
    case forgotPassword
    case chatStream
    case generateImage
    case viewImage(id: String)
    case transcribeVoice
    case userProfile
    case updateUserProfile
    case uploadProfilePhoto
    case deleteProfilePhoto
    case resetUserProfile
    case userCharacters
    case userCharacter(id: String)

    public static var aiHealth: APIEndpoint { .healthAI }
    public static var imageGenerate: APIEndpoint { .generateImage }
    public static func imageView(id: String) -> APIEndpoint { .viewImage(id: id) }

    public func url(with config: APIConfiguration) -> URL {
        let base = config.baseURL
        switch self {
        case .health:
            return base.appendingPathComponent("api/health")
        case .healthAI:
            return base.appendingPathComponent("api/health/ai")
        case .register:
            return base.appendingPathComponent("api/auth/register")
        case .login:
            return base.appendingPathComponent("api/auth/login")
        case .googleAuth:
            return base.appendingPathComponent("api/auth/google")
        case .me:
            return base.appendingPathComponent("api/auth/me")
        case .logout:
            return base.appendingPathComponent("api/auth/logout")
        case .forgotPassword:
            return base.appendingPathComponent("api/auth/forgot-password")
        case .chatStream:
            return base.appendingPathComponent("api/chat/stream")
        case .generateImage:
            return base.appendingPathComponent("api/image/generate")
        case .viewImage(let id):
            return base.appendingPathComponent("api/image/view/\(id)")
        case .transcribeVoice:
            return base.appendingPathComponent("api/voice/transcribe")
        case .userProfile, .updateUserProfile, .resetUserProfile:
            return base.appendingPathComponent("api/user/profile")
        case .uploadProfilePhoto, .deleteProfilePhoto:
            return base.appendingPathComponent("api/user/profile/photo")
        case .userCharacters:
            return base.appendingPathComponent("api/user/characters")
        case .userCharacter(let id):
            return base.appendingPathComponent("api/user/characters/\(id)")
        }
    }

    public var httpMethod: String {
        switch self {
        case .health, .healthAI, .me, .viewImage, .userProfile, .userCharacters:
            return "GET"
        case .register, .login, .googleAuth, .logout, .forgotPassword, .chatStream, .generateImage, .transcribeVoice, .uploadProfilePhoto:
            return "POST"
        case .updateUserProfile:
            return "PUT"
        case .deleteProfilePhoto, .resetUserProfile, .userCharacter:
            return "DELETE"
        }
    }
}

public struct GoogleAuthRequest: Codable {
    public let id_token: String

    public init(idToken: String) {
        self.id_token = idToken
    }
}

public struct ForgotPasswordRequest: Codable {
    public let email: String

    public init(email: String) {
        self.email = email
    }
}

public struct ForgotPasswordResponse: Codable {
    public let message: String
}

public struct UpdateProfileRequest: Codable {
    public let custom_name: String?
    public let bio: String?
    public let avatar_emoji: String?
    public let avatar_color_hex: String?

    public init(
        customName: String?,
        bio: String?,
        avatarEmoji: String?,
        avatarColorHex: String?
    ) {
        self.custom_name = customName
        self.bio = bio
        self.avatar_emoji = avatarEmoji
        self.avatar_color_hex = avatarColorHex
    }
}

public struct UploadPhotoPayload: Codable {
    public let image: String

    public init(image: String) {
        self.image = image
    }
}

public struct CustomCharacterPayload: Codable {
    public let id: String?
    public let name: String
    public let system_prompt: String
    public let avatar_emoji: String

    public init(
        id: String? = nil,
        name: String,
        systemPrompt: String,
        avatarEmoji: String
    ) {
        self.id = id
        self.name = name
        self.system_prompt = systemPrompt
        self.avatar_emoji = avatarEmoji
    }
}

public struct CustomCharacterRemote: Codable, Identifiable {
    public let id: String
    public let name: String
    public let system_prompt: String
    public let avatar_emoji: String

    public init(
        id: String,
        name: String,
        systemPrompt: String,
        avatarEmoji: String
    ) {
        self.id = id
        self.name = name
        self.system_prompt = systemPrompt
        self.avatar_emoji = avatarEmoji
    }
}
