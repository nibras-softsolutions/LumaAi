import Foundation

public protocol ConversationStoreProtocol: AnyObject {
    func loadConversations(for userId: String) -> [Conversation]
    func saveConversations(_ conversations: [Conversation], for userId: String)
    func deleteConversations(for userId: String)
}

public final class ConversationStore: ConversationStoreProtocol {
    public static let shared = ConversationStore()

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private func fileURL(for userId: String) -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sanitized = userId.replacingOccurrences(of: "/", with: "_")
        return docs.appendingPathComponent("luma_conversations_\(sanitized).json")
    }

    public func loadConversations(for userId: String) -> [Conversation] {
        guard !userId.isEmpty else { return [] }
        let url = fileURL(for: userId)
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Conversation].self, from: data)
        } catch {
            print("Failed to load conversations: \(error)")
            return []
        }
    }

    public func saveConversations(_ conversations: [Conversation], for userId: String) {
        guard !userId.isEmpty else { return }
        let url = fileURL(for: userId)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(conversations)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }

    public func deleteConversations(for userId: String) {
        guard !userId.isEmpty else { return }
        let url = fileURL(for: userId)
        try? fileManager.removeItem(at: url)
    }
}
