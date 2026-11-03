import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public struct LumaWidgetSnapshot: Codable, Equatable {
    public var isAuthenticated: Bool
    public var userName: String?
    public var userAvatarEmoji: String?
    public var userAvatarColorHex: String?
    public var recentPromptTitle: String?
    public var activePersonaName: String?
    public var activePersonaEmoji: String?
    public var lastUpdated: Date

    public init(
        isAuthenticated: Bool = false,
        userName: String? = nil,
        userAvatarEmoji: String? = nil,
        userAvatarColorHex: String? = nil,
        recentPromptTitle: String? = nil,
        activePersonaName: String? = "Luma AI",
        activePersonaEmoji: String? = "✨",
        lastUpdated: Date = Date()
    ) {
        self.isAuthenticated = isAuthenticated
        self.userName = userName
        self.userAvatarEmoji = userAvatarEmoji
        self.userAvatarColorHex = userAvatarColorHex
        self.recentPromptTitle = recentPromptTitle
        self.activePersonaName = activePersonaName
        self.activePersonaEmoji = activePersonaEmoji
        self.lastUpdated = lastUpdated
    }

    public static var placeholder: LumaWidgetSnapshot {
        LumaWidgetSnapshot(
            isAuthenticated: true,
            userName: "Nibras",
            userAvatarEmoji: "👤",
            userAvatarColorHex: "#FFC43D",
            recentPromptTitle: "Brainstorm creative gift ideas for an architect",
            activePersonaName: "Luma AI",
            activePersonaEmoji: "✨",
            lastUpdated: Date()
        )
    }

    public static var loggedOut: LumaWidgetSnapshot {
        LumaWidgetSnapshot(
            isAuthenticated: false,
            userName: nil,
            userAvatarEmoji: nil,
            userAvatarColorHex: nil,
            recentPromptTitle: nil,
            activePersonaName: "Luma AI",
            activePersonaEmoji: "✨",
            lastUpdated: Date()
        )
    }
}

public final class LumaWidgetStore {
    public static let shared = LumaWidgetStore()
    public static let appGroupId = "group.me.tapfolio.app"
    private let storageKey = "luma_shared_widget_snapshot"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupId) ?? .standard
    }

    public init() {}

    public func sync(
        isAuthenticated: Bool,
        userName: String? = nil,
        userAvatarEmoji: String? = nil,
        userAvatarColorHex: String? = nil,
        recentPromptTitle: String? = nil,
        activePersonaName: String? = nil,
        activePersonaEmoji: String? = nil
    ) {
        var current = loadSnapshot()
        current.isAuthenticated = isAuthenticated
        if let userName = userName { current.userName = userName }
        if let userAvatarEmoji = userAvatarEmoji { current.userAvatarEmoji = userAvatarEmoji }
        if let userAvatarColorHex = userAvatarColorHex { current.userAvatarColorHex = userAvatarColorHex }
        if let recentPromptTitle = recentPromptTitle { current.recentPromptTitle = recentPromptTitle }
        if let activePersonaName = activePersonaName { current.activePersonaName = activePersonaName }
        if let activePersonaEmoji = activePersonaEmoji { current.activePersonaEmoji = activePersonaEmoji }
        current.lastUpdated = Date()

        saveSnapshot(current)
        reloadWidgetTimelines()
    }

    public func updateRecentPrompt(_ prompt: String) {
        var current = loadSnapshot()
        current.recentPromptTitle = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        current.lastUpdated = Date()
        saveSnapshot(current)
        reloadWidgetTimelines()
    }

    public func clearAuth() {
        var current = loadSnapshot()
        current.isAuthenticated = false
        current.recentPromptTitle = nil
        current.userName = nil
        current.lastUpdated = Date()
        saveSnapshot(current)
        reloadWidgetTimelines()
    }

    public func saveSnapshot(_ snapshot: LumaWidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func loadSnapshot() -> LumaWidgetSnapshot {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(LumaWidgetSnapshot.self, from: data) else {
            return .loggedOut
        }
        return snapshot
    }

    public func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

