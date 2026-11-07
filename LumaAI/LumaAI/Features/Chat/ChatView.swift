import SwiftUI

public struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var userPreferences: UserPreferences
    let currentUser: User?
    let onOpenHistory: () -> Void
    let onOpenVoice: () -> Void
    let onOpenSettings: () -> Void

    @State private var showingImageDetail: Bool = false
    @State private var showingTextScanner: Bool = false
    private var externalScannerBinding: Binding<Bool>?

    private var scannerBinding: Binding<Bool> {
        externalScannerBinding ?? $showingTextScanner
    }

    public init(
        viewModel: ChatViewModel,
        userPreferences: UserPreferences = .shared,
        currentUser: User? = nil,
        isTextScannerPresented: Binding<Bool>? = nil,
        onOpenHistory: @escaping () -> Void,
        onOpenVoice: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.userPreferences = userPreferences
        self.currentUser = currentUser
        self.externalScannerBinding = isTextScannerPresented
        self.onOpenHistory = onOpenHistory
        self.onOpenVoice = onOpenVoice
        self.onOpenSettings = onOpenSettings
    }

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return "Good Morning,"
        } else if hour < 17 {
            return "Good Afternoon,"
        } else {
            return "Good Evening,"
        }
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
        ZStack {
            // Orbix Studio Angled Soft Lavender Background
            OrbixBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Orbix Studio Navigation Header
                orbixHeader

                // Main Conversation & Empty State Area
                ScrollViewReader { proxy in
                    ZStack {
                        // Dismiss keyboard tap target
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismissKeyboard()
                            }

                        if viewModel.conversation.messages.isEmpty {
                            emptyOrbixChatGreeting
                        } else {
                            messageScrollView(proxy: proxy)
                        }
                    }
                    .onChange(of: viewModel.conversation.messages.count) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: viewModel.conversation.messages.last?.content) { _ in
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }

                // Error Banner if present
                if let error = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color.lumaError)
                        Text(error)
                            .font(LumaTypography.caption)
                            .foregroundColor(Color.lumaError)
                        Spacer()
                        Button(action: { viewModel.errorMessage = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundColor(Color.orbixSecondaryText)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.lumaError.opacity(0.1))
                }

                // Quick Vision Actions when photo is attached
                if viewModel.attachedImage != nil && !viewModel.isStreaming {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            photoActionChip(title: "🔍 Explain photo", prompt: "Please explain and analyze what is shown in this photo in detail.")
                            photoActionChip(title: "📝 Extract text", prompt: "Extract and transcribe all readable text, labels, and content in this image.")
                            photoActionChip(title: "💡 What is this?", prompt: "Identify what is in this picture and give key facts about it.")
                            photoActionChip(title: "🛠️ How to solve / fix", prompt: "Analyze the problem or situation shown in this photo and explain how to address it step-by-step.")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Orbix Studio Composer Bar
                ComposerView(
                    text: $viewModel.inputText,
                    attachedImage: $viewModel.attachedImage,
                    isStreaming: viewModel.isStreaming,
                    isImageMode: viewModel.isImageMode,
                    isDictating: viewModel.isDictating,
                    speechAudioLevel: viewModel.speechAudioLevel,
                    onToggleImageMode: {
                        withAnimation(.spring(response: 0.25)) {
                            viewModel.isImageMode.toggle()
                        }
                    },
                    onScanText: {
                        dismissKeyboard()
                        scannerBinding.wrappedValue = true
                    },
                    onToggleVoice: {
                        viewModel.toggleDictation()
                    },
                    onOpenVoiceMode: onOpenVoice,
                    onSend: {
                        viewModel.sendMessage()
                    },
                    onStop: {
                        viewModel.stopStreaming()
                    }
                )
                .padding(.bottom, 6)
            }
        }
        .sheet(item: $viewModel.selectedImageAttachment) { attachment in
            ImageViewerView(attachment: attachment)
        }
        .fullScreenCover(isPresented: scannerBinding) {
            LiveTextScannerView(
                onInsertText: { recognizedText in
                    scannerBinding.wrappedValue = false
                    DispatchQueue.main.async {
                        let text = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        if viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            viewModel.inputText = text
                        } else {
                            viewModel.inputText += "\n" + text
                        }
                    }
                },
                onDismiss: {
                    scannerBinding.wrappedValue = false
                }
            )
        }
    }

    // MARK: - Orbix Studio Navigation Header
    private var orbixHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // User Avatar (matching reference top-left circular portrait)
            Button(action: {
                HapticFeedback.light()
                dismissKeyboard()
                onOpenSettings()
            }) {
                UserProfileAvatarView(
                    userPreferences: userPreferences,
                    currentUser: currentUser,
                    size: 42
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open profile and settings")

            // User Name & Greeting (matching reference: Good Morning, Jhonathon Troot)
            VStack(alignment: .leading, spacing: 2) {
                Text(timeGreeting)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.orbixSecondaryText)

                Text(displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.orbixPrimaryText)
                    .lineLimit(1)
            }

            Spacer()

            // History / Drawer Button
            Button(action: {
                HapticFeedback.light()
                dismissKeyboard()
                onOpenHistory()
            }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.orbixPrimaryText)
                    .frame(width: 38, height: 38)
                    .background(Color.lumaSurface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.orbixCardBorder, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            }

            // New Conversation Button
            Button(action: {
                HapticFeedback.light()
                dismissKeyboard()
                viewModel.startNewConversation()
            }) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.orbixPrimaryText)
                    .frame(width: 38, height: 38)
                    .background(Color.lumaSurface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.orbixCardBorder, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: - Orbix Studio Empty State
    private var emptyOrbixChatGreeting: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)

                    // Hero Text (Matching reference image: "Need anything?")
                    VStack(spacing: 12) {
                        Text("Need anything?")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(Color.orbixPrimaryText)
                            .multilineTextAlignment(.center)

                        Text("Our smart AI assistant helps you find exactly what you need—faster and easier than ever.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(Color.orbixSecondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 32)
                    }

                    // Prompt Suggestion Chips (Matching reference layout below search bar)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            promptChip(icon: "gift", title: "Best gift ideas", query: "Give me creative gift ideas for a loved one")
                            promptChip(icon: "sparkles", title: "Creative brainstorm", query: "Brainstorm 5 innovative startup concepts in AI")
                            promptChip(icon: "curlybraces", title: "Swift architecture", query: "How do I build a scalable SwiftUI architecture?")
                            promptChip(icon: "figure.run", title: "Fitness plan", query: "Design a high-energy 30-minute daily workout routine")
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(
                DragGesture(minimumDistance: 6).onChanged { _ in
                    dismissKeyboard()
                }
            )
        }
    }

    private func promptChip(icon: String, title: String, query: String) -> some View {
        Button(action: {
            HapticFeedback.light()
            dismissKeyboard()
            viewModel.inputText = query
            viewModel.sendMessage()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.orbixSecondaryText)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Color.orbixPrimaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.lumaSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.orbixCardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func photoActionChip(title: String, prompt: String) -> some View {
        Button(action: {
            HapticFeedback.light()
            dismissKeyboard()
            viewModel.inputText = prompt
            viewModel.sendMessage()
        }) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.orbixPrimaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.lumaSurfaceElevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.orbixCardBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message List
    private func messageScrollView(proxy: ScrollViewProxy) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 14) {
                ForEach(viewModel.conversation.messages) { message in
                    MessageBubbleView(message: message) { attachment in
                        viewModel.selectedImageAttachment = attachment
                    }
                    .id(message.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(
            DragGesture(minimumDistance: 6).onChanged { _ in
                dismissKeyboard()
            }
        )
        .defaultScrollAnchor(.bottom)
        .onAppear {
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = viewModel.conversation.messages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
