import SwiftUI

public struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onOpenHistory: () -> Void
    let onOpenVoice: () -> Void
    let onOpenSettings: () -> Void

    @State private var showingImageDetail: Bool = false

    public init(
        viewModel: ChatViewModel,
        onOpenHistory: @escaping () -> Void,
        onOpenVoice: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onOpenHistory = onOpenHistory
        self.onOpenVoice = onOpenVoice
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        ZStack {
            Color.lumaCanvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                navigationHeader

                Divider()

                // Messages Scroll Area
                if viewModel.conversation.messages.isEmpty {
                    emptyChatGreeting
                } else {
                    messageScrollView
                }

                // Error Banner if present
                if let error = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.lumaError)
                        Text(error)
                            .font(LumaTypography.caption)
                            .foregroundColor(.lumaError)
                        Spacer()
                        Button(action: { viewModel.errorMessage = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundColor(.lumaSecondaryText)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.lumaError.opacity(0.1))
                }

                // Bottom Composer
                ComposerView(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.isStreaming,
                    isImageMode: viewModel.isImageMode,
                    onToggleImageMode: {
                        withAnimation(.spring(response: 0.25)) {
                            viewModel.isImageMode.toggle()
                        }
                    },
                    onStartVoice: onOpenVoice,
                    onSend: {
                        viewModel.sendMessage()
                    },
                    onStop: {
                        viewModel.stopStreaming()
                    }
                )
            }
        }
        .sheet(item: $viewModel.selectedImageAttachment) { attachment in
            ImageViewerView(attachment: attachment)
        }
    }

    private var navigationHeader: some View {
        HStack(spacing: 12) {
            Button(action: {
                HapticFeedback.light()
                onOpenHistory()
            }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 18))
                    .foregroundColor(.lumaPrimaryText)
                    .frame(width: 38, height: 38)
                    .background(Color.lumaSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.conversation.title)
                    .font(LumaTypography.headline)
                    .foregroundColor(.lumaPrimaryText)
                    .lineLimit(1)

                Text(viewModel.isStreaming ? "Responding…" : "Luma AI")
                    .font(LumaTypography.caption)
                    .foregroundColor(.lumaSecondaryText)
            }

            Spacer()

            Button(action: {
                HapticFeedback.light()
                viewModel.startNewConversation()
            }) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17))
                    .foregroundColor(.lumaPrimaryText)
                    .frame(width: 38, height: 38)
                    .background(Color.lumaSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button(action: {
                HapticFeedback.light()
                onOpenSettings()
            }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
                    .foregroundColor(.lumaSecondaryText)
                    .frame(width: 38, height: 38)
                    .background(Color.lumaSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.lumaCanvas)
    }

    private var emptyChatGreeting: some View {
        VStack(spacing: 28) {
            Spacer()

            Circle()
                .fill(Color.lumaSurfaceElevated)
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: "sparkle")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.lumaPrimaryText)
                )

            VStack(spacing: 8) {
                Text("How can I help you think today?")
                    .font(LumaTypography.title)
                    .foregroundColor(.lumaPrimaryText)
                    .multilineTextAlignment(.center)

                Text("Ask questions, explore complex topics, generate code, or create artwork.")
                    .font(LumaTypography.subheadline)
                    .foregroundColor(.lumaSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Quick Starter Suggestions
            VStack(spacing: 10) {
                promptStarter("Explain quantum computing in simple terms")
                promptStarter("Write a Swift function to debounce network calls")
                promptStarter("Generate an image of a serene mountain lake at dawn")
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func promptStarter(_ prompt: String) -> some View {
        Button(action: {
            HapticFeedback.light()
            viewModel.inputText = prompt
            viewModel.sendMessage()
        }) {
            HStack {
                Text(prompt)
                    .font(LumaTypography.subheadline)
                    .foregroundColor(.lumaPrimaryText)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(.lumaTertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.lumaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.lumaBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.conversation.messages) { message in
                        MessageBubbleView(message: message) { attachment in
                            viewModel.selectedImageAttachment = attachment
                        }
                        .id(message.id)
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.conversation.messages.last?.content) { _ in
                if let last = viewModel.conversation.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}
