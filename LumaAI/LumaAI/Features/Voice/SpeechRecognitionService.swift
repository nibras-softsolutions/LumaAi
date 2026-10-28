import Foundation
import Speech
import AVFoundation

public enum SpeechPermissionStatus {
    case notDetermined
    case authorized
    case denied
}

@MainActor
public final class SpeechRecognitionService: ObservableObject {
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var recognizedText: String = ""
    @Published public private(set) var permissionStatus: SpeechPermissionStatus = .notDetermined
    @Published public var audioLevel: Float = 0.0

    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    public init() {
        checkPermissions()
    }

    public func checkPermissions() {
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        switch authStatus {
        case .authorized:
            self.permissionStatus = .authorized
        case .denied, .restricted:
            self.permissionStatus = .denied
        case .notDetermined:
            self.permissionStatus = .notDetermined
        @unknown default:
            self.permissionStatus = .notDetermined
        }
    }

    public func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micAuthorized = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        let granted = speechAuthorized && micAuthorized
        self.permissionStatus = granted ? .authorized : .denied
        return granted
    }

    public func startRecording(onTranscript: @escaping (String, Bool) -> Void) throws {
        stopRecording()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            self?.recognitionRequest?.append(buffer)

            // Calculate rough audio RMS level for orb pulsing
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = UInt(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<Int(frameLength) {
                    sum += abs(channelData[i])
                }
                let avg = frameLength > 0 ? sum / Float(frameLength) : 0
                DispatchQueue.main.async {
                    self?.audioLevel = min(1.0, avg * 10.0)
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        recognizedText = ""

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.recognizedText = transcription
                    onTranscript(transcription, result.isFinal)
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.stopRecording()
                }
            }
        }
    }

    public func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        audioLevel = 0.0
    }
}
