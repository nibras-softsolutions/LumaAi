import SwiftUI

public enum NavigationDestination: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case imagine = "Imagine"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .chat:
            return "bubble.left.and.bubble.right.fill"
        case .imagine:
            return "sparkles.rectangle.stack.fill"
        }
    }
}

public struct AppSidebarView: View {
    @Binding var selectedDestination: NavigationDestination
    @Binding var isOpen: Bool
    @ObservedObject var chatViewModel: ChatViewModel
    @ObservedObject var userPreferences: UserPreferences
    let currentUser: User?
    let conversationStore: ConversationStoreProtocol
    let userId: String
    let onOpenSettings: () -> Void

    @State private var conversations: [Conversation] = []
    @State private var dragOffset: CGFloat = 0

    public init(
        selectedDestination: Binding<NavigationDestination>,
        isOpen: Binding<Bool>,
        chatViewModel: ChatViewModel,
        userPreferences: UserPreferences = .shared,
        currentUser: User? = nil,
        conversationStore: ConversationStoreProtocol = ConversationStore.shared,
        userId: String,
        onOpenSettings: @escaping () -> Void
    ) {
        self._selectedDestination = selectedDestination
        self._isOpen = isOpen
        self.chatViewModel = chatViewModel
        self.userPreferences = userPreferences
        self.currentUser = currentUser
        self.conversationStore = conversationStore
        self.userId = userId
        self.onOpenSettings = onOpenSettings
    }

    private var displayName: String {
        if let custom = userPreferences.customDisplayName, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom.trimmingCharacters(in: .whitespaces)
        }
        if let user = currentUser, !user.fullName.trimmingCharacters(in: .whitespaces).isEmpty {
            return user.fullName.trimmingCharacters(in: .whitespaces)
        }
        return "Luma User"
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            Color.orbixBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // 1. Sidebar Header (Branding & Dismiss Button)
                sidebarHeader
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 16)

                // 2. New Chat Quick Action
                Button(action: {
                    HapticFeedback.light()
                    chatViewModel.startNewConversation()
                    selectedDestination = .chat
                    closeSidebar()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.orbixPurple)

                        Text("New Chat")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.orbixPrimaryText)

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.lumaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.orbixCardBorder, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start a new chat")
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                // 3. Navigation Destinations (Chat & Imagine)
                VStack(spacing: 4) {
                    destinationRow(destination: .chat)
                    destinationRow(destination: .imagine)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)

                Divider()
                    .overlay(Color.orbixCardBorder)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // 4. Conversation History Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("RECENT CHATS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.orbixSecondaryText)
                            .textCase(.uppercase)

                        Spacer()

                        if !conversations.isEmpty {
                            Text("\(conversations.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.orbixSecondaryText.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 20)

                    if conversations.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 20))
                                .foregroundColor(Color.orbixSecondaryText.opacity(0.6))
                            Text("No recent conversations")
                                .font(.system(size: 13))
                                .foregroundColor(Color.orbixSecondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 4) {
                                ForEach(conversations) { conv in
                                    conversationItemRow(conv)
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                }

                Spacer()

                Divider()
                    .overlay(Color.orbixCardBorder)
                    .padding(.horizontal, 16)

                // 5. User Profile & Settings Row (Bottom)
                userSettingsFooter
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .offset(x: min(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.width < 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.translation.width < -60 || value.predictedEndTranslation.width < -120 {
                        closeSidebar()
                    }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
        )
        .onAppear {
            loadRecentConversations()
        }
        .onChange(of: isOpen) { open in
            if open {
                loadRecentConversations()
            }
        }
    }

    // MARK: - Subviews

    private var sidebarHeader: some View {
        HStack(alignment: .center) {
            // Luma AI Emblem
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.orbixPurple)
                        .frame(width: 32, height: 32)
                        .shadow(color: Color.orbixPurple.opacity(0.3), radius: 6, x: 0, y: 2)

                    Image(systemName: "sparkle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }

                Text("Luma AI")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.orbixPrimaryText)
            }

            Spacer()

            // Close Button
            Button(action: {
                HapticFeedback.light()
                closeSidebar()
            }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.orbixPrimaryText)
                    .frame(width: 36, height: 36)
                    .background(Color.lumaSurface)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.orbixCardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close sidebar")
        }
    }

    private func destinationRow(destination: NavigationDestination) -> some View {
        let isSelected = selectedDestination == destination

        return Button(action: {
            HapticFeedback.light()
            selectedDestination = destination
            closeSidebar()
        }) {
            HStack(spacing: 12) {
                Image(systemName: destination.icon)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? Color.orbixPurple : Color.orbixSecondaryText)
                    .frame(width: 24)

                Text(destination.rawValue)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Color.orbixPrimaryText : Color.orbixPrimaryText.opacity(0.85))

                Spacer()

                if isSelected {
                    Circle()
                        .fill(Color.orbixPurple)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(isSelected ? Color.orbixLavender.opacity(0.45) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.rawValue)
    }

    private func conversationItemRow(_ conv: Conversation) -> some View {
        let isCurrent = chatViewModel.conversation.id == conv.id && selectedDestination == .chat

        return Button(action: {
            HapticFeedback.light()
            chatViewModel.setConversation(conv)
            selectedDestination = .chat
            closeSidebar()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isCurrent ? Color.orbixPurple : Color.orbixSecondaryText)

                Text(conv.title)
                    .font(.system(size: 13.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? Color.orbixPrimaryText : Color.orbixPrimaryText.opacity(0.85))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isCurrent ? Color.lumaSurface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isCurrent ? Color.orbixCardBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: {
                deleteConversation(conv)
            }) {
                Label("Delete Chat", systemImage: "trash")
            }
        }
    }

    private var userSettingsFooter: some View {
        Button(action: {
            HapticFeedback.light()
            closeSidebar()
            onOpenSettings()
        }) {
            HStack(spacing: 10) {
                // User Avatar Circle
                UserProfileAvatarView(
                    userPreferences: userPreferences,
                    currentUser: currentUser,
                    size: 38
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.orbixPrimaryText)
                        .lineLimit(1)

                    Text("Preferences & Personas")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color.orbixSecondaryText)
                }

                Spacer()

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15))
                    .foregroundColor(Color.orbixSecondaryText)
                    .frame(width: 32, height: 32)
                    .background(Color.lumaSurface)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.orbixCardBorder, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Settings and Profile")
    }

    private func loadRecentConversations() {
        self.conversations = conversationStore.loadConversations(for: userId)
        Task {
            if let remote = try? await APIClient.shared.fetchConversations(), !remote.isEmpty {
                await MainActor.run {
                    self.conversations = remote
                    self.conversationStore.saveConversations(remote, for: self.userId)
                }
            }
        }
    }

    private func deleteConversation(_ conv: Conversation) {
        conversations.removeAll { $0.id == conv.id }
        conversationStore.saveConversations(conversations, for: userId)
        if chatViewModel.conversation.id == conv.id {
            chatViewModel.startNewConversation()
        }
        let id = conv.id
        Task {
            try? await APIClient.shared.deleteConversation(id: id)
        }
    }

    private func closeSidebar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isOpen = false
        }
    }
}
