import Foundation
import SwiftUI
import Combine

@MainActor
public final class VoiceViewModel: ObservableObject {
    @Published public var state: VoiceState = .listening
    @Published public var userTranscript: String = "Listening…"
    @Published public var assistantTranscript: String = ""
    @Published public var isMuted: Bool = false
    @Published public var errorMessage: String?
    @Published public var lastSpokenText: String = ""

    public let speechService: SpeechRecognitionService
    public let ttsService: TextToSpeechService

    private let apiClient: APIClientProtocol
    private var silenceTimer: Timer?
    private var streamingTask: Task<Void, Never>?
    private var speechQueue: [String] = []
    private var currentTurnId: Int = 0

    public init(
        apiClient: APIClientProtocol,
        speechService: SpeechRecognitionService? = nil,
        ttsService: TextToSpeechService? = nil
    ) {
        self.apiClient = apiClient
        self.speechService = speechService ?? SpeechRecognitionService()
        self.ttsService = ttsService ?? TextToSpeechService()
    }

    public func startSession() async {
        let authorized = await speechService.requestPermissions()
        guard authorized else {
            errorMessage = "Microphone and speech recognition permissions are required for Voice Mode."
            state = .muted
            return
        }

        startListening()
    }

    public func stopSession() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        streamingTask?.cancel()
        streamingTask = nil
        speechService.stopRecording()
        ttsService.stop()
    }

    public func startListening() {
        guard !isMuted else {
            state = .muted
            return
        }

        state = .listening
        userTranscript = "Listening…"
        silenceTimer?.invalidate()

        do {
            try speechService.startRecording { [weak self] transcript, isFinal in
                guard let self = self else { return }
                guard self.state == .listening && !self.isMuted else { return }

                let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    self.userTranscript = clean

                    // Reset silence timer
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: isFinal ? 0.7 : 1.2, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            if self?.state == .listening {
                                self?.submitTurn(clean)
                            }
                        }
                    }
                }
            }
        } catch {
            errorMessage = "Could not start audio recording: \(error.localizedDescription)"
        }
    }

    public func submitTurn(_ text: String) {
        guard !text.isEmpty else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        speechService.stopRecording()

        currentTurnId += 1
        let turnId = currentTurnId
        state = .thinking
        assistantTranscript = "…"
        speechQueue.removeAll()

        let userMsg = ChatMessage(role: .user, content: text)
        let messages = [userMsg]

        streamingTask = Task {
            var fullAssistantReply = ""
            var sentenceBuffer = ""

            do {
                try await apiClient.ensureSession()
            } catch {
                print("[LumaAI] VoiceViewModel: ensureSession failed: \(error.localizedDescription)")
            }

            do {
                let stream = apiClient.streamChat(messages: messages)
                for try await event in stream {
                    guard !Task.isCancelled, turnId == currentTurnId else { break }

                    switch event {
                    case .token(let chunk):
                        fullAssistantReply += chunk
                        self.assistantTranscript = fullAssistantReply
                        sentenceBuffer += chunk

                        if let sentence = extractSentence(from: &sentenceBuffer) {
                            enqueueSpeech(sentence, turnId: turnId)
                        }
                    case .image:
                        break
                    case .error(let msg):
                        self.errorMessage = msg
                    case .done:
                        break
                    case .unknown:
                        break
                    }
                }

                if !sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    enqueueSpeech(sentenceBuffer, turnId: turnId)
                }

                self.lastSpokenText = fullAssistantReply

                if fullAssistantReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let fallback = self.errorMessage ?? "I didn't receive a response. Please check your connection and try again."
                    self.assistantTranscript = fallback
                    enqueueSpeech(fallback, turnId: turnId)
                }
            } catch {
                if !Task.isCancelled && turnId == currentTurnId {
                    let errorText = "I couldn't reach the server. Please try again."
                    self.errorMessage = error.localizedDescription
                    self.assistantTranscript = errorText
                    enqueueSpeech(errorText, turnId: turnId)
                }
            }
        }
    }

    private func extractSentence(from buffer: inout String) -> String? {
        let pattern = "([.!?]+)(?=\\s|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }

        let nsString = buffer as NSString
        if let match = regex.firstMatch(in: buffer, options: [], range: NSRange(location: 0, length: nsString.length)) {
            let endIndex = match.range.location + match.range.length
            let sentence = nsString.substring(with: NSRange(location: 0, length: endIndex)).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = nsString.substring(from: endIndex).trimmingCharacters(in: .whitespaces)
            return sentence.isEmpty ? nil : sentence
        }
        return nil
    }

    private func enqueueSpeech(_ sentence: String, turnId: Int) {
        guard turnId == currentTurnId else { return }
        speechQueue.append(sentence)
        if !ttsService.isSpeaking {
            playNextSpeech(turnId: turnId)
        }
    }

    private func playNextSpeech(turnId: Int) {
        guard turnId == currentTurnId else { return }

        if speechQueue.isEmpty {
            state = .listening
            userTranscript = "Listening…"
            // Brief settle window before listening again so speaker output is not heard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self, self.state == .listening, !self.isMuted else { return }
                self.startListening()
            }
            return
        }

        let nextSentence = speechQueue.removeFirst()
        state = .speaking

        ttsService.speak(nextSentence) { [weak self] in
            guard let self = self, self.currentTurnId == turnId else { return }
            self.playNextSpeech(turnId: turnId)
        }
    }

    public func handleOrbTap() {
        if state == .speaking {
            interrupt()
        } else if state == .listening {
            if !speechService.recognizedText.isEmpty {
                submitTurn(speechService.recognizedText)
            }
        } else if state == .muted {
            toggleMute()
        }
    }

    public func interrupt() {
        currentTurnId += 1
        speechQueue.removeAll()
        ttsService.stop()
        streamingTask?.cancel()
        streamingTask = nil
        startListening()
    }

    public func toggleMute() {
        isMuted.toggle()
        if isMuted {
            stopSession()
            state = .muted
            userTranscript = "Microphone muted"
        } else {
            startListening()
        }
    }

    public func replayLastResponse() {
        guard !lastSpokenText.isEmpty, state != .speaking else { return }
        interrupt()
        enqueueSpeech(lastSpokenText, turnId: currentTurnId)
    }
}
