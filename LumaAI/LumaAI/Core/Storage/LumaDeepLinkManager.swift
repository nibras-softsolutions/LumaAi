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
    @Published public var sharedImage: UIImage?

    private init() {}

    @discardableResult
    public func handle(url: URL) -> Bool {
        // Handle direct image file URLs (e.g. shared from Apple Photos or Files app)
        let ext = url.pathExtension.lowercased()
        if url.isFileURL || ["jpg", "jpeg", "png", "heic", "webp", "tiff"].contains(ext) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.sharedImage = img
                    self.activeDestination = .chat
                }
                return true
            }
        }

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

