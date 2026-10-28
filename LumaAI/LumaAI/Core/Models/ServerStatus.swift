import Foundation

public struct ServerHealth: Codable, Equatable {
    public let status: String

    public init(status: String) {
        self.status = status
    }
}

public struct AIHealthStatus: Codable, Equatable {
    public let status: String
    public let model: String?
    public let ollamaConnected: Bool?
    public let modelAvailable: Bool?

    enum CodingKeys: String, CodingKey {
        case status
        case model
        case ollamaConnected = "ollama_connected"
        case modelAvailable = "model_available"
    }
}

public struct VoiceTranscriptionResponse: Codable {
    public let text: String
}
