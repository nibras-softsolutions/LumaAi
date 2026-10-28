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
        }
    }

    public var httpMethod: String {
        switch self {
        case .health, .healthAI, .me, .viewImage:
            return "GET"
        case .register, .login, .googleAuth, .logout, .forgotPassword, .chatStream, .generateImage, .transcribeVoice:
            return "POST"
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
