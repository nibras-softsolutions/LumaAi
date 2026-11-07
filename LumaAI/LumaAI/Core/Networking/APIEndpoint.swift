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
    case getConversations
    case saveConversation
    case deleteConversation(id: String)
    case clearAllConversations
    case syncConversations
    case signingKey

    public static var aiHealth: APIEndpoint { .healthAI }
    public static var imageGenerate: APIEndpoint { .generateImage }
    public static func imageView(id: String) -> APIEndpoint { .viewImage(id: id) }

    public func url(with config: APIConfiguration) -> URL {
        let base = config.baseURL
        let path: String
        switch self {
        case .health:
            path = "api/health"
        case .healthAI:
            path = "api/health/ai"
        case .register:
            path = "api/auth/register"
        case .login:
            path = "api/auth/login"
        case .googleAuth:
            path = "api/auth/google"
        case .me:
            path = "api/auth/me"
        case .logout:
            path = "api/auth/logout"
        case .forgotPassword:
            path = "api/auth/forgot-password"
        case .chatStream:
            path = "api/chat/stream"
        case .generateImage:
            path = "api/image/generate"
        case .viewImage(let id):
            path = "api/image/view/\(id)"
        case .transcribeVoice:
            path = "api/voice/transcribe"
        case .userProfile, .updateUserProfile, .resetUserProfile:
            path = "api/user/profile"
        case .uploadProfilePhoto, .deleteProfilePhoto:
            path = "api/user/profile/photo"
        case .userCharacters:
            path = "api/user/characters"
        case .userCharacter(let id):
            path = "api/user/characters/\(id)"
        case .getConversations, .saveConversation, .clearAllConversations:
            path = "api/chat/conversations"
        case .deleteConversation(let id):
            path = "api/chat/conversations/\(id)"
        case .syncConversations:
            path = "api/chat/sync"
        case .signingKey:
            path = "api/auth/signing-key"
        }

        if #available(iOS 16.0, macOS 13.0, *) {
            return base.appending(path: path)
        } else {
            var result = base
            for segment in path.split(separator: "/") {
                result = result.appendingPathComponent(String(segment))
            }
            return result
        }
    }

    public var httpMethod: String {
        switch self {
        case .health, .healthAI, .me, .viewImage, .userProfile, .userCharacters, .getConversations:
            return "GET"
        case .register, .login, .googleAuth, .logout, .forgotPassword, .chatStream, .generateImage, .transcribeVoice, .uploadProfilePhoto, .saveConversation, .syncConversations, .signingKey:
            return "POST"
        case .updateUserProfile:
            return "PUT"
        case .deleteProfilePhoto, .resetUserProfile, .userCharacter, .deleteConversation, .clearAllConversations:
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
