import Foundation
import SwiftUI
import Combine

public enum ServiceStatusState: Equatable {
    case loading
    case operational
    case degraded
    case unavailable
}

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var serverHealth: ServerHealth?
    @Published public var aiHealth: AIHealthStatus?
    @Published public var isCheckingHealth: Bool = false
    @Published public var healthError: String?
    @Published public var lastCheckedTime: Date?
    @Published public var latencyMs: Int?
    @Published public var isPlayingSample: Bool = false

    public let authManager: AuthenticationManager
    public let userPreferences: UserPreferences
    private let apiClient: APIClientProtocol
    private let ttsService = TextToSpeechService()

    public init(
        authManager: AuthenticationManager,
        userPreferences: UserPreferences = .shared,
        apiClient: APIClientProtocol
    ) {
        self.authManager = authManager
        self.userPreferences = userPreferences
        self.apiClient = apiClient
    }

    public var statusState: ServiceStatusState {
        if isCheckingHealth || (serverHealth == nil && healthError == nil) {
            return .loading
        }
        if let err = healthError, !err.isEmpty {
            return .unavailable
        }
        guard let health = serverHealth, health.status == "ok" else {
            return .unavailable
        }
        if let ai = aiHealth {
            if ai.modelAvailable == true {
                return .operational
            } else {
                return .degraded
            }
        }
        return .operational
    }

    public var formattedLastChecked: String {
        guard let date = lastCheckedTime else { return "Not checked yet" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Checked at \(formatter.string(from: date))"
    }

    public func checkServerHealth() async {
        isCheckingHealth = true
        healthError = nil
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            async let healthReq = apiClient.checkHealth()
            async let aiHealthReq = apiClient.checkAIHealth()

            let (health, ai) = try await (healthReq, aiHealthReq)
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            self.serverHealth = health
            self.aiHealth = ai
            self.latencyMs = max(1, elapsed)
            self.lastCheckedTime = Date()
        } catch {
            self.healthError = error.localizedDescription
            self.lastCheckedTime = Date()
            self.latencyMs = nil
        }

        self.isCheckingHealth = false
    }

    public func playVoiceSample() {
        if isPlayingSample {
            ttsService.stop()
            isPlayingSample = false
            return
        }

        isPlayingSample = true
        ttsService.speak("Hi, I'm Luma AI. I'm ready to think, create, and explore with you.") { [weak self] in
            DispatchQueue.main.async {
                self?.isPlayingSample = false
            }
        }
    }

    public func resetVoiceSettings() {
        ttsService.stop()
        isPlayingSample = false
        userPreferences.voiceSpeakingRate = 0.49
        userPreferences.voicePitchMultiplier = 1.10
    }

    public func logout() async {
        ttsService.stop()
        isPlayingSample = false
        await authManager.logout()
    }
}
