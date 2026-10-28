import SwiftUI

public struct MainContainerView: View {
    @EnvironmentObject var appEnv: AppEnvironment
    @State private var selectedTab: Int = 0

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: AI Chat
            ChatView(
                viewModel: appEnv.chatViewModel,
                onOpenHistory: {
                    appEnv.showingHistory = true
                },
                onOpenVoice: {
                    appEnv.openVoiceMode()
                },
                onOpenSettings: {
                    appEnv.showingSettings = true
                }
            )
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(0)

            // Tab 2: Imagine (AI Image Generation)
            ImageGenerationView(apiClient: appEnv.apiClient)
                .tabItem {
                    Label("Imagine", systemImage: "sparkles.rectangle.stack")
                }
                .tag(1)
        }
        .tint(.lumaPrimaryText)
        .sheet(isPresented: $appEnv.showingHistory) {
            let userId = appEnv.authManager.currentUser?.id ?? "anonymous"
            HistoryView(
                userId: userId,
                conversationStore: appEnv.conversationStore,
                onSelectConversation: { conv in
                    appEnv.chatViewModel.setConversation(conv)
                },
                onNewConversation: {
                    appEnv.chatViewModel.startNewConversation()
                }
            )
        }
        .sheet(isPresented: $appEnv.showingSettings) {
            SettingsView(
                authManager: appEnv.authManager,
                userPreferences: appEnv.userPreferences,
                apiClient: appEnv.apiClient
            )
        }
        .fullScreenCover(isPresented: $appEnv.showingVoiceMode) {
            if let voiceVM = appEnv.voiceViewModel {
                VoiceConversationView(viewModel: voiceVM) {
                    appEnv.closeVoiceMode()
                }
            }
        }
    }
}
