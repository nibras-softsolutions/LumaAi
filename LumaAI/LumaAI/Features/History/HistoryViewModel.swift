import Foundation
import SwiftUI
import Combine

@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public var conversations: [Conversation] = []
    @Published public var searchQuery: String = ""

    private let conversationStore: ConversationStoreProtocol
    private let userId: String

    public init(
        conversationStore: ConversationStoreProtocol = ConversationStore.shared,
        userId: String
    ) {
        self.conversationStore = conversationStore
        self.userId = userId
        loadConversations()
    }

    public var filteredConversations: [Conversation] {
        let cleanQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanQuery.isEmpty {
            return conversations
        }
        return conversations.filter { conv in
            conv.title.lowercased().contains(cleanQuery) ||
            conv.messages.contains(where: { $0.content.lowercased().contains(cleanQuery) })
        }
    }

    public func loadConversations() {
        self.conversations = conversationStore.loadConversations(for: userId)
    }

    public func deleteConversation(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { filteredConversations[$0] }
        conversations.removeAll { item in
            itemsToDelete.contains(where: { $0.id == item.id })
        }
        conversationStore.saveConversations(conversations, for: userId)
    }

    public func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        conversationStore.saveConversations(conversations, for: userId)
    }

    public func clearAll() {
        conversations.removeAll()
        conversationStore.deleteConversations(for: userId)
    }
}
