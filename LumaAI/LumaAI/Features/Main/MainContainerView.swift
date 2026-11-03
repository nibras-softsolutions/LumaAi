import SwiftUI

public struct MainContainerView: View {
    @EnvironmentObject var appEnv: AppEnvironment
    @State private var selectedDestination: NavigationDestination = .chat
    @State private var isSidebarOpen: Bool = false

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 1. Main Content Area (No bottom navigation bar)
                Group {
                    switch selectedDestination {
                    case .chat:
                        ChatView(
                            viewModel: appEnv.chatViewModel,
                            userPreferences: appEnv.userPreferences,
                            currentUser: appEnv.authManager.currentUser,
                            isTextScannerPresented: $appEnv.showingTextScanner,
                            onOpenHistory: {
                                openSidebar()
                            },
                            onOpenVoice: {
                                appEnv.openVoiceMode()
                            },
                            onOpenSettings: {
                                appEnv.showingSettings = true
                            }
                        )
                    case .imagine:
                        ImageGenerationView(
                            apiClient: appEnv.apiClient,
                            onOpenSidebar: {
                                openSidebar()
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .fullScreenCover(isPresented: $appEnv.showingVoiceMode) {
                    if let voiceVM = appEnv.voiceViewModel {
                        VoiceConversationView(viewModel: voiceVM) {
                            appEnv.closeVoiceMode()
                        }
                    }
                }

                // 2. Dimmed Overlay Backdrop when Sidebar is Open
                if isSidebarOpen {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeSidebar()
                        }
                        .transition(.opacity)
                        .zIndex(200)

                    // 3. ChatGPT-Style Sliding Sidebar
                    AppSidebarView(
                        selectedDestination: $selectedDestination,
                        isOpen: $isSidebarOpen,
                        chatViewModel: appEnv.chatViewModel,
                        userPreferences: appEnv.userPreferences,
                        currentUser: appEnv.authManager.currentUser,
                        conversationStore: appEnv.conversationStore,
                        userId: appEnv.authManager.currentUser?.id ?? "anonymous",
                        onOpenSettings: {
                            appEnv.showingSettings = true
                        }
                    )
                    .frame(width: min(geometry.size.width * 0.82, 320))
                    .transition(.move(edge: .leading))
                    .zIndex(201)
                }
            }
        }
        .sheet(isPresented: $appEnv.showingHistory) {
            let userId = appEnv.authManager.currentUser?.id ?? "anonymous"
            HistoryView(
                userId: userId,
                conversationStore: appEnv.conversationStore,
                onSelectConversation: { conv in
                    appEnv.chatViewModel.setConversation(conv)
                    selectedDestination = .chat
                },
                onNewConversation: {
                    appEnv.chatViewModel.startNewConversation()
                    selectedDestination = .chat
                }
            )
        }
        .fullScreenCover(isPresented: $appEnv.showingSettings) {
            SettingsView(
                authManager: appEnv.authManager,
                userPreferences: appEnv.userPreferences,
                apiClient: appEnv.apiClient
            )
        }
    }

    private func openSidebar() {
        // Resign keyboard if active before opening sidebar
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isSidebarOpen = true
        }
    }

    private func closeSidebar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isSidebarOpen = false
        }
    }
}
