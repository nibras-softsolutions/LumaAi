import Foundation
import SwiftUI
import Combine

@MainActor
public final class AppEnvironment: ObservableObject {
    public let apiClient: APIClientProtocol
    public let authManager: AuthenticationManager
    public let conversationStore: ConversationStoreProtocol
    public let userPreferences: UserPreferences

    @Published public var chatViewModel: ChatViewModel
    @Published public var showingVoiceMode: Bool = false
    @Published public var showingHistory: Bool = false
    @Published public var showingSettings: Bool = false
    @Published public var voiceViewModel: VoiceViewModel?

    private var cancellables = Set<AnyCancellable>()

    public init(
        apiClient: APIClientProtocol = APIClient.shared,
        authManager: AuthenticationManager? = nil,
        conversationStore: ConversationStoreProtocol = ConversationStore.shared,
        userPreferences: UserPreferences = .shared
    ) {
        self.apiClient = apiClient
        let resolvedAuth = authManager ?? AuthenticationManager(apiClient: apiClient)
        self.authManager = resolvedAuth
        self.conversationStore = conversationStore
        self.userPreferences = userPreferences

        let currentUserId = resolvedAuth.currentUser?.id ?? "anonymous"
        self.chatViewModel = ChatViewModel(
            apiClient: apiClient,
            conversationStore: conversationStore,
            userId: currentUserId
        )

        // Observe auth state changes to re-key chatViewModel with new user's conversations
        resolvedAuth.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newUser in
                guard let self = self else { return }
                let newId = newUser?.id ?? "anonymous"
                self.chatViewModel = ChatViewModel(
                    apiClient: self.apiClient,
                    conversationStore: self.conversationStore,
                    userId: newId
                )
            }
            .store(in: &cancellables)
    }

    public func openVoiceMode() {
        voiceViewModel = VoiceViewModel(apiClient: apiClient)
        showingVoiceMode = true
    }

    public func closeVoiceMode() {
        voiceViewModel?.stopSession()
        voiceViewModel = nil
        showingVoiceMode = false
    }
}
