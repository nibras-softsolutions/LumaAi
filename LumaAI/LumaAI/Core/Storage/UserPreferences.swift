import Foundation
import Combine

public final class UserPreferences: ObservableObject {
    public static let shared = UserPreferences()

    private let defaults: UserDefaults

    @Published public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    @Published public var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }

    @Published public var voiceSpeakingRate: Float {
        didSet { defaults.set(voiceSpeakingRate, forKey: "voiceSpeakingRate") }
    }

    @Published public var voicePitchMultiplier: Float {
        didSet { defaults.set(voicePitchMultiplier, forKey: "voicePitchMultiplier") }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        self.voiceSpeakingRate = defaults.object(forKey: "voiceSpeakingRate") as? Float ?? 0.49
        self.voicePitchMultiplier = defaults.object(forKey: "voicePitchMultiplier") as? Float ?? 1.10
    }
}
