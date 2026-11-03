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
    @Published public var showingTextScanner: Bool = false
    @Published public var requestComposerFocus: Bool = false
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

                // Sync shared WidgetKit storage
                let isAuth = newUser != nil
                let name = self.userPreferences.customDisplayName ?? newUser?.fullName
                let persona = self.userPreferences.activeCharacter
                LumaWidgetStore.shared.sync(
                    isAuthenticated: isAuth,
                    userName: name,
                    userAvatarEmoji: self.userPreferences.customAvatarEmoji,
                    userAvatarColorHex: self.userPreferences.customAvatarColorHex,
                    activePersonaName: persona.name,
                    activePersonaEmoji: persona.avatarEmoji
                )
            }
            .store(in: &cancellables)

        // Forward auth and preferences changes so observing views re-render instantly
        resolvedAuth.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        userPreferences.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.objectWillChange.send()

                let isAuth = self.authManager.isAuthenticated
                let name = self.userPreferences.customDisplayName ?? self.authManager.currentUser?.fullName
                let persona = self.userPreferences.activeCharacter
                LumaWidgetStore.shared.sync(
                    isAuthenticated: isAuth,
                    userName: name,
                    userAvatarEmoji: self.userPreferences.customAvatarEmoji,
                    userAvatarColorHex: self.userPreferences.customAvatarColorHex,
                    activePersonaName: persona.name,
                    activePersonaEmoji: persona.avatarEmoji
                )
            }
            .store(in: &cancellables)

        // Handle App Intent deep links
        LumaDeepLinkManager.shared.$activeDestination
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] dest in
                self?.handleDeepLink(destination: dest)
            }
            .store(in: &cancellables)
    }

    public func handleDeepLink(url: URL) {
        LumaDeepLinkManager.shared.handle(url: url)
    }

    public func handleDeepLink(destination: LumaDeepLinkDestination) {
        guard authManager.isAuthenticated else {
            showingSettings = false
            showingVoiceMode = false
            showingTextScanner = false
            return
        }

        showingSettings = false

        switch destination {
        case .chat:
            showingVoiceMode = false
            showingTextScanner = false
            requestComposerFocus = true
        case .voice:
            showingTextScanner = false
            openVoiceMode()
        case .camera, .scan:
            showingVoiceMode = false
            showingTextScanner = true
        }
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
