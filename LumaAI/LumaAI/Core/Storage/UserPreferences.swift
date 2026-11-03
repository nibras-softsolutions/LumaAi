import Foundation
import Combine

public final class UserPreferences: ObservableObject {
    public static let shared = UserPreferences()

    private let defaults: UserDefaults
    private let customCharactersKey = "luma_custom_characters"

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

    // MARK: - Profile Customization

    @Published public var customDisplayName: String? {
        didSet { defaults.set(customDisplayName, forKey: "customDisplayName") }
    }

    @Published public var customBio: String? {
        didSet { defaults.set(customBio, forKey: "customBio") }
    }

    @Published public var customAvatarEmoji: String? {
        didSet { defaults.set(customAvatarEmoji, forKey: "customAvatarEmoji") }
    }

    @Published public var customAvatarColorHex: String? {
        didSet { defaults.set(customAvatarColorHex, forKey: "customAvatarColorHex") }
    }

    @Published public var customProfileImageData: Data? {
        didSet { defaults.set(customProfileImageData, forKey: "customProfileImageData") }
    }

    @Published public var remoteProfileImageUrl: String? {
        didSet { defaults.set(remoteProfileImageUrl, forKey: "remoteProfileImageUrl") }
    }

    // MARK: - Custom Characters & Personas

    @Published public var activeCharacterId: String {
        didSet { defaults.set(activeCharacterId, forKey: "activeCharacterId") }
    }

    @Published public var userCharacters: [CustomCharacter] = [] {
        didSet { saveUserCharacters() }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        self.voiceSpeakingRate = defaults.object(forKey: "voiceSpeakingRate") as? Float ?? 0.49
        self.voicePitchMultiplier = defaults.object(forKey: "voicePitchMultiplier") as? Float ?? 1.10

        self.customDisplayName = defaults.string(forKey: "customDisplayName")
        self.customBio = defaults.string(forKey: "customBio")
        self.customAvatarEmoji = defaults.string(forKey: "customAvatarEmoji")
        self.customAvatarColorHex = defaults.string(forKey: "customAvatarColorHex")
        self.customProfileImageData = defaults.data(forKey: "customProfileImageData")
        self.remoteProfileImageUrl = defaults.string(forKey: "remoteProfileImageUrl")

        self.activeCharacterId = defaults.string(forKey: "activeCharacterId") ?? "char_luma_default"

        loadUserCharacters()
    }

    public var hasCustomProfile: Bool {
        customDisplayName != nil || customBio != nil || customAvatarEmoji != nil || customProfileImageData != nil || remoteProfileImageUrl != nil
    }

    public func resetProfileCustomization() {
        customDisplayName = nil
        customBio = nil
        customAvatarEmoji = nil
        customAvatarColorHex = nil
        customProfileImageData = nil
        remoteProfileImageUrl = nil
    }

    public func syncWithServerUser(_ user: User, client: APIClientProtocol = APIClient.shared) {
        if let customName = user.customName, !customName.isEmpty {
            self.customDisplayName = customName
        }
        if let bio = user.bio, !bio.isEmpty {
            self.customBio = bio
        }
        if let avatarEmoji = user.avatarEmoji, !avatarEmoji.isEmpty {
            self.customAvatarEmoji = avatarEmoji
        }
        if let avatarColorHex = user.avatarColorHex, !avatarColorHex.isEmpty {
            self.customAvatarColorHex = avatarColorHex
        }

        if let remoteUrl = user.profileImageUrl, !remoteUrl.isEmpty {
            let previousUrl = self.remoteProfileImageUrl
            self.remoteProfileImageUrl = remoteUrl

            // If remote URL is set and we either don't have local data or URL changed:
            if previousUrl != remoteUrl || self.customProfileImageData == nil {
                Task { [weak self] in
                    do {
                        let data = try await client.downloadImageData(from: remoteUrl)
                        await MainActor.run {
                            self?.customProfileImageData = data
                        }
                    } catch {
                        print("[UserPreferences] Error downloading profile picture: \(error)")
                    }
                }
            }
        } else if user.profileImageUrl == nil {
            self.remoteProfileImageUrl = nil
            self.customProfileImageData = nil
        }
    }

    // MARK: - Character Management

    public var allCharacters: [CustomCharacter] {
        CustomCharacter.builtInCharacters + userCharacters
    }

    public var activeCharacter: CustomCharacter {
        allCharacters.first(where: { $0.id == activeCharacterId }) ?? CustomCharacter.builtInCharacters[0]
    }

    public func addCustomCharacter(_ character: CustomCharacter) {
        userCharacters.append(character)
    }

    public func updateCustomCharacter(_ character: CustomCharacter) {
        if let idx = userCharacters.firstIndex(where: { $0.id == character.id }) {
            userCharacters[idx] = character
        }
    }

    public func deleteCustomCharacter(id: String) {
        userCharacters.removeAll(where: { $0.id == id })
        if activeCharacterId == id {
            activeCharacterId = "char_luma_default"
        }
    }

    private func loadUserCharacters() {
        guard let data = defaults.data(forKey: customCharactersKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([CustomCharacter].self, from: data)
            self.userCharacters = decoded
        } catch {
            print("[UserPreferences] Error decoding custom characters: \(error)")
        }
    }

    private func saveUserCharacters() {
        do {
            let data = try JSONEncoder().encode(userCharacters)
            defaults.set(data, forKey: customCharactersKey)
        } catch {
            print("[UserPreferences] Error encoding custom characters: \(error)")
        }
    }
}
