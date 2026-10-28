import SwiftUI

public struct HistoryView: View {
    @StateObject private var viewModel: HistoryViewModel
    let onSelectConversation: (Conversation) -> Void
    let onNewConversation: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showingClearConfirmation: Bool = false

    public init(
        userId: String,
        conversationStore: ConversationStoreProtocol = ConversationStore.shared,
        onSelectConversation: @escaping (Conversation) -> Void,
        onNewConversation: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: HistoryViewModel(conversationStore: conversationStore, userId: userId))
        self.onSelectConversation = onSelectConversation
        self.onNewConversation = onNewConversation
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.lumaCanvas
                    .ignoresSafeArea()

                if viewModel.conversations.isEmpty {
                    EmptyStateView(
                        icon: "clock.arrow.circlepath",
                        title: "No Chat History",
                        message: "Your conversations are saved locally on this device.",
                        actionTitle: "Start New Chat"
                    ) {
                        onNewConversation()
                        dismiss()
                    }
                } else {
                    List {
                        ForEach(viewModel.filteredConversations) { conv in
                            conversationRow(conv)
                                .listRowBackground(Color.lumaSurface)
                                .listRowSeparatorTint(Color.lumaBorder)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    HapticFeedback.light()
                                    onSelectConversation(conv)
                                    dismiss()
                                }
                        }
                        .onDelete(perform: viewModel.deleteConversation)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .searchable(text: $viewModel.searchQuery, prompt: "Search past conversations…")
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(LumaTypography.body)
                    .foregroundColor(.lumaPrimaryText)
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !viewModel.conversations.isEmpty {
                        Button(action: {
                            showingClearConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 15))
                                .foregroundColor(.lumaError)
                        }
                    }

                    Button(action: {
                        HapticFeedback.light()
                        onNewConversation()
                        dismiss()
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16))
                            .foregroundColor(.lumaAccent)
                    }
                }
            }
            .confirmationDialog(
                "Clear All History?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Conversations", role: .destructive) {
                    HapticFeedback.warning()
                    viewModel.clearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all conversation history stored on this device. This cannot be undone.")
            }
            .onAppear {
                viewModel.loadConversations()
            }
        }
    }

    private func conversationRow(_ conv: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(conv.title)
                    .font(LumaTypography.headline)
                    .foregroundColor(.lumaPrimaryText)
                    .lineLimit(1)

                Spacer()

                Text(formatDate(conv.updatedAt))
                    .font(LumaTypography.caption)
                    .foregroundColor(.lumaTertiaryText)
            }

            if let lastMessage = conv.messages.last {
                Text(lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(LumaTypography.caption)
                    .foregroundColor(.lumaSecondaryText)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 10))
                    .foregroundColor(.lumaTertiaryText)
                Text("\(conv.messages.count) messages")
                    .font(LumaTypography.caption)
                    .foregroundColor(.lumaTertiaryText)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
