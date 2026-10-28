import Foundation

public struct ImageGenerateRequest: Codable {
    public let prompt: String
    public let aspectRatio: String

    public init(prompt: String, aspectRatio: String = "1:1") {
        self.prompt = prompt
        self.aspectRatio = aspectRatio
    }

    enum CodingKeys: String, CodingKey {
        case prompt
        case aspectRatio = "aspect_ratio"
    }
}

public struct ImageGenerateResponse: Codable, Identifiable, Equatable {
    public let id: String
    public let prompt: String
    public let aspectRatio: String
    public let imageUrl: String
    public let width: Int
    public let height: Int
    public let provider: String
    public let model: String
    public let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case aspectRatio = "aspect_ratio"
        case imageUrl = "image_url"
        case width
        case height
        case provider
        case model
        case createdAt = "created_at"
    }
}
