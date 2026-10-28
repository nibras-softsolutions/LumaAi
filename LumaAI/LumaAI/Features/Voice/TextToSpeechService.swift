import Foundation
import AVFoundation

public final class TextToSpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published public private(set) var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private var onFinishedHandler: (() -> Void)?
    private var cachedVoice: AVSpeechSynthesisVoice?

    public override init() {
        super.init()
        synthesizer.delegate = self
        self.cachedVoice = resolveBestFemaleVoice()
    }

    public func speak(_ text: String, onFinished: (() -> Void)? = nil) {
        stop()

        self.onFinishedHandler = onFinished
        let cleanText = sanitizeForSpeech(text)
        guard !cleanText.isEmpty else {
            onFinished?()
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .voiceChat, options: [.duckOthers, .defaultToSpeaker])
        try? audioSession.setActive(true)

        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.voice = cachedVoice ?? resolveBestFemaleVoice()
        utterance.rate = UserPreferences.shared.voiceSpeakingRate
        utterance.pitchMultiplier = UserPreferences.shared.voicePitchMultiplier
        utterance.volume = 1.0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
            self?.onFinishedHandler?()
            self?.onFinishedHandler = nil
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
            self?.onFinishedHandler = nil
        }
    }

    private func resolveBestFemaleVoice() -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let englishVoices = allVoices.filter { $0.language.lowercased().hasPrefix("en") }

        // 1. Enhanced / Premium Samantha on Apple devices
        if let samanthaEnhanced = englishVoices.first(where: {
            $0.name.lowercased().contains("samantha") && $0.quality == .enhanced
        }) {
            return samanthaEnhanced
        }

        // 2. Standard Samantha
        if let samantha = englishVoices.first(where: {
            $0.name.lowercased().contains("samantha")
        }) {
            return samantha
        }

        // 3. Known natural female voices (Ava, Nora, Serena, Karen, Tessa)
        let femaleNames = ["ava", "nora", "serena", "karen", "tessa", "zoe", "allison"]
        for name in femaleNames {
            if let v = englishVoices.first(where: { $0.name.lowercased().contains(name) }) {
                return v
            }
        }

        // 4. Default English voice
        if let defaultEn = AVSpeechSynthesisVoice(language: "en-US") {
            return defaultEn
        }

        return AVSpeechSynthesisVoice(language: Locale.current.identifier)
    }

    private func sanitizeForSpeech(_ text: String) -> String {
        var clean = text
        clean = clean.replacingOccurrences(of: "```[\\s\\S]*?```", with: "Here is the code snippet.", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "https?://\\S+", with: "link", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "[*#_~]", with: "", options: .regularExpression)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
