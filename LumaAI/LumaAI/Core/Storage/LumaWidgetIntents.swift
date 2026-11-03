import Foundation
import AppIntents

public struct OpenChatIntent: AppIntent {
    public static var title: LocalizedStringResource = "Ask Luma"
    public static var description = IntentDescription("Opens Luma AI directly into the chat composer.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        LumaDeepLinkManager.shared.handle(destination: .chat)
        return .result()
    }
}

public struct OpenVoiceIntent: AppIntent {
    public static var title: LocalizedStringResource = "Voice Mode"
    public static var description = IntentDescription("Opens Luma AI voice assistant.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        LumaDeepLinkManager.shared.handle(destination: .voice)
        return .result()
    }
}

public struct OpenCameraIntent: AppIntent {
    public static var title: LocalizedStringResource = "Camera"
    public static var description = IntentDescription("Opens the camera in Luma AI.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        LumaDeepLinkManager.shared.handle(destination: .camera)
        return .result()
    }
}

public struct OpenScanIntent: AppIntent {
    public static var title: LocalizedStringResource = "Scan Text"
    public static var description = IntentDescription("Opens live OCR text scanning in Luma AI.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        LumaDeepLinkManager.shared.handle(destination: .scan)
        return .result()
    }
}

