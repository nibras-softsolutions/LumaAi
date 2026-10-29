import Foundation
import SwiftUI
import Combine

@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public var conversation: Conversation
    @Published public var inputText: String = ""
    @Published public var isStreaming: Bool = false
    @Published public var isImageMode: Bool = false
    @Published public var errorMessage: String?
    @Published public var selectedImageAttachment: ImageAttachment?
    @Published public var attachedImage: UIImage? = nil
    @Published public var isDictating: Bool = false
    @Published public var speechAudioLevel: Float = 0.0

    private let apiClient: APIClientProtocol
    private let conversationStore: ConversationStoreProtocol
    private let userId: String
    private var streamingTask: Task<Void, Never>?
    private let speechService = SpeechRecognitionService()
    private var cancellables = Set<AnyCancellable>()

    public init(
        conversation: Conversation = Conversation(),
        apiClient: APIClientProtocol,
        conversationStore: ConversationStoreProtocol = ConversationStore.shared,
        userId: String
    ) {
        self.conversation = conversation
        self.apiClient = apiClient
        self.conversationStore = conversationStore
        self.userId = userId

        speechService.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.speechAudioLevel = level
            }
            .store(in: &cancellables)

        speechService.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                if !recording && self?.isDictating == true {
                    self?.isDictating = false
                }
            }
            .store(in: &cancellables)
    }

    public func setConversation(_ newConv: Conversation) {
        stopStreaming()
        stopDictation()
        self.conversation = newConv
        self.inputText = ""
        self.attachedImage = nil
        self.errorMessage = nil
    }

    public func startNewConversation() {
        stopStreaming()
        stopDictation()
        self.conversation = Conversation()
        self.inputText = ""
        self.attachedImage = nil
        self.errorMessage = nil
    }

    public func toggleDictation() {
        if isDictating {
            stopDictation()
        } else {
            startDictation()
        }
    }

    public func startDictation() {
        Task { @MainActor in
            let granted = await speechService.requestPermissions()
            guard granted else {
                self.errorMessage = "Speech recognition and microphone access are required for voice input. Please enable them in iOS Settings."
                return
            }

            self.isDictating = true
            let initialText = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                try speechService.startRecording { [weak self] transcript, isFinal in
                    guard let self = self else { return }
                    if initialText.isEmpty {
                        self.inputText = transcript
                    } else {
                        self.inputText = "\(initialText) \(transcript)"
                    }
                    if isFinal {
                        self.isDictating = false
                    }
                }
            } catch {
                self.isDictating = false
                self.errorMessage = "Could not start voice input: \(error.localizedDescription)"
            }
        }
    }

    public func stopDictation() {
        speechService.stopRecording()
        isDictating = false
        speechAudioLevel = 0.0
    }

    public func sendMessage() {
        if isDictating {
            stopDictation()
        }

        let cleanText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!cleanText.isEmpty || attachedImage != nil), !isStreaming else { return }

        // Clear input immediately
        inputText = ""
        errorMessage = nil

        var attachment: ImageAttachment? = nil
        if let img = attachedImage, let jpegData = img.jpegData(compressionQuality: 0.7) {
            let base64 = jpegData.base64EncodedString()
            attachment = ImageAttachment(
                id: UUID().uuidString,
                prompt: cleanText.isEmpty ? "Image upload" : cleanText,
                aspectRatio: "1:1",
                imageUrl: "data:image/jpeg;base64,\(base64)",
                width: Int(img.size.width),
                height: Int(img.size.height),
                provider: "user_upload",
                model: "user"
            )
        }
        attachedImage = nil

        let messageText = cleanText.isEmpty ? (attachment != nil ? "Attached an image." : "") : cleanText

        // Add user message
        let userMessage = ChatMessage(role: .user, content: messageText, status: .complete, imageAttachment: attachment)
        conversation.messages.append(userMessage)

        // Generate title if first message
        if conversation.messages.filter({ $0.role == .user }).count == 1 {
            let titleSource = cleanText.isEmpty ? "Image Conversation" : cleanText
            let words = titleSource.split(separator: " ").prefix(5).joined(separator: " ")
            conversation.title = words.isEmpty ? "New Conversation" : words
        }
        conversation.updatedAt = Date()
        persistConversation()

        if isImageMode {
            generateImage(prompt: cleanText)
        } else {
            streamAssistantReply()
        }
    }

    private func streamAssistantReply() {
        isStreaming = true
        let assistantMessageId = UUID()
        let assistantMessage = ChatMessage(id: assistantMessageId, role: .assistant, content: "", status: .streaming)
        conversation.messages.append(assistantMessage)

        streamingTask = Task {
            print("[LumaAI] ChatViewModel: streamAssistantReply started for \(assistantMessageId)")
            do {
                try await apiClient.ensureSession()
            } catch {
                print("[LumaAI] ChatViewModel: ensureSession failed: \(error.localizedDescription)")
            }

            var tokenCount = 0
            do {
                let stream = apiClient.streamChat(messages: conversation.messages)
                for try await event in stream {
                    guard !Task.isCancelled else { break }

                    switch event {
                    case .token(let text):
                        tokenCount += 1
                        self.objectWillChange.send()
                        if let idx = conversation.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            conversation.messages[idx].content += text
                        }
                    case .image(let attachment):
                        self.objectWillChange.send()
                        if let idx = conversation.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            conversation.messages[idx].imageAttachment = attachment
                        }
                    case .error(let msg):
                        self.objectWillChange.send()
                        if let idx = conversation.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            conversation.messages[idx].errorMessage = msg
                            conversation.messages[idx].status = .failed
                        }
                        self.errorMessage = msg
                    case .done:
                        self.objectWillChange.send()
                        if let idx = conversation.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            conversation.messages[idx].status = .complete
                        }
                    case .unknown:
                        break
                    }
                }

                self.objectWillChange.send()
                if let idx = conversation.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    if conversation.messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        conversation.messages[idx].status = .failed
                        let fallback = self.errorMessage ?? "No response received from model. Please try again."
                        conversation.messages[idx].errorMessage = fallback
                        self.errorMessage = fallback
                    } else if conversation.messages[idx].status == .streaming {
                        conversation.messages[idx].status = .complete
                    }
                }
                print("[LumaAI] ChatViewModel: stream finished. Total tokens received: \(tokenCount)")
            } catch {
                if !Task.isCancelled {
                    let errMsg = error.localizedDescription
                    print("[LumaAI] ChatViewModel: stream caught error: \(errMsg)")
                    self.objectWillChange.send()
                    if let idx = conversation.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                        conversation.messages[idx].errorMessage = errMsg
                        conversation.messages[idx].status = .failed
                    }
                    self.errorMessage = errMsg
                }
            }

            self.isStreaming = false
            self.conversation.updatedAt = Date()
            self.persistConversation()
        }
    }

    private func generateImage(prompt: String) {
        isStreaming = true
        let assistantMessageId = UUID()
        let placeholder = ChatMessage(id: assistantMessageId, role: .assistant, content: "Generating image…", status: .streaming)
        conversation.messages.append(placeholder)

        Task {
            do {
                let response = try await apiClient.generateImage(prompt: prompt, aspectRatio: "1:1")
                let attachment = ImageAttachment(
                    id: response.id,
                    prompt: response.prompt,
                    aspectRatio: response.aspectRatio,
                    imageUrl: response.imageUrl,
                    width: response.width,
                    height: response.height,
                    provider: response.provider,
                    model: response.model
                )

                if let idx = conversation.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    conversation.messages[idx].content = "Here is your generated image."
                    conversation.messages[idx].imageAttachment = attachment
                    conversation.messages[idx].status = .complete
                }
            } catch {
                let errMsg = error.localizedDescription
                if let idx = conversation.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    conversation.messages[idx].content = "Image generation failed."
                    conversation.messages[idx].errorMessage = errMsg
                    conversation.messages[idx].status = .failed
                }
                self.errorMessage = errMsg
            }

            self.isStreaming = false
            self.conversation.updatedAt = Date()
            self.persistConversation()
        }
    }

    public func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        if let last = conversation.messages.last, last.status == .streaming {
            if let idx = conversation.messages.indices.last {
                conversation.messages[idx].status = .complete
            }
        }
        persistConversation()
    }

    private func persistConversation() {
        var all = conversationStore.loadConversations(for: userId)
        if let idx = all.firstIndex(where: { $0.id == conversation.id }) {
            all[idx] = conversation
        } else {
            all.insert(conversation, at: 0)
        }
        conversationStore.saveConversations(all, for: userId)
    }
}
