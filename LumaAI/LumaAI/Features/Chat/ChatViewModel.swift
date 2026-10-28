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

    private let apiClient: APIClientProtocol
    private let conversationStore: ConversationStoreProtocol
    private let userId: String
    private var streamingTask: Task<Void, Never>?

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
    }

    public func setConversation(_ newConv: Conversation) {
        stopStreaming()
        self.conversation = newConv
        self.inputText = ""
        self.errorMessage = nil
    }

    public func startNewConversation() {
        stopStreaming()
        self.conversation = Conversation()
        self.inputText = ""
        self.errorMessage = nil
    }

    public func sendMessage() {
        let cleanText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, !isStreaming else { return }

        // Clear input immediately
        inputText = ""
        errorMessage = nil

        // Add user message
        let userMessage = ChatMessage(role: .user, content: cleanText, status: .complete)
        conversation.messages.append(userMessage)

        // Generate title if first message
        if conversation.messages.filter({ $0.role == .user }).count == 1 {
            let words = cleanText.split(separator: " ").prefix(5).joined(separator: " ")
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
