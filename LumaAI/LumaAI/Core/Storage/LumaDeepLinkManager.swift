import Foundation
import SwiftUI

public enum LumaDeepLinkDestination: String, Codable, CaseIterable {
    case chat
    case voice
    case camera
    case scan

    public var url: URL {
        URL(string: "luma://\(rawValue)")!
    }
}

public final class LumaDeepLinkManager: ObservableObject {
    public static let shared = LumaDeepLinkManager()

    @Published public var activeDestination: LumaDeepLinkDestination?

    private init() {}

    @discardableResult
    public func handle(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "luma" else { return false }
        let raw = (url.host?.isEmpty == false ? url.host : url.path.replacingOccurrences(of: "/", with: ""))?.lowercased() ?? "chat"
        let dest = LumaDeepLinkDestination(rawValue: raw) ?? .chat
        handle(destination: dest)
        return true
    }

    public func handle(destination: LumaDeepLinkDestination) {
        DispatchQueue.main.async {
            self.activeDestination = destination
        }
    }

    public func consumeDestination() -> LumaDeepLinkDestination? {
        let dest = activeDestination
        activeDestination = nil
        return dest
    }
}

