import Foundation

public enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

public enum MessageStatus: String, Codable {
    case sending
    case streaming
    case complete
    case failed
}

public struct ImageAttachment: Codable, Equatable, Identifiable {
    public let id: String
    public let prompt: String
    public let aspectRatio: String
    public let imageUrl: String
    public let width: Int
    public let height: Int
    public let provider: String
    public let model: String

    public init(
        id: String,
        prompt: String,
        aspectRatio: String,
        imageUrl: String,
        width: Int,
        height: Int,
        provider: String,
        model: String
    ) {
        self.id = id
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.imageUrl = imageUrl
        self.width = width
        self.height = height
        self.provider = provider
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case aspectRatio = "aspect_ratio"
        case imageUrl = "image_url"
        case width
        case height
        case provider
        case model
    }
}

public struct ChatMessage: Codable, Identifiable, Equatable {
    public let id: UUID
    public let role: MessageRole
    public var content: String
    public var status: MessageStatus
    public var errorMessage: String?
    public var imageAttachment: ImageAttachment?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        status: MessageStatus = .complete,
        errorMessage: String? = nil,
        imageAttachment: ImageAttachment? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
        self.errorMessage = errorMessage
        self.imageAttachment = imageAttachment
        self.createdAt = createdAt
    }
}

public struct SendMessagePayload: Codable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatStreamRequest: Codable {
    public let messages: [SendMessagePayload]

    public init(messages: [SendMessagePayload]) {
        self.messages = messages
    }
}
