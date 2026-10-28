import Foundation
import SwiftUI
import Combine

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var serverHealth: ServerHealth?
    @Published public var aiHealth: AIHealthStatus?
    @Published public var isCheckingHealth: Bool = false
    @Published public var healthError: String?

    public let authManager: AuthenticationManager
    public let userPreferences: UserPreferences
    private let apiClient: APIClientProtocol

    public init(
        authManager: AuthenticationManager,
        userPreferences: UserPreferences = .shared,
        apiClient: APIClientProtocol
    ) {
        self.authManager = authManager
        self.userPreferences = userPreferences
        self.apiClient = apiClient
    }

    public func checkServerHealth() async {
        isCheckingHealth = true
        healthError = nil

        do {
            async let healthReq = apiClient.checkHealth()
            async let aiHealthReq = apiClient.checkAIHealth()

            let (health, ai) = try await (healthReq, aiHealthReq)
            self.serverHealth = health
            self.aiHealth = ai
        } catch {
            self.healthError = error.localizedDescription
        }

        self.isCheckingHealth = false
    }

    public func resetVoiceSettings() {
        userPreferences.voiceSpeakingRate = 0.49
        userPreferences.voicePitchMultiplier = 1.10
    }

    public func logout() async {
        await authManager.logout()
    }
}
