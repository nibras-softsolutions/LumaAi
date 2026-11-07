import SwiftUI

public struct UserProfileAvatarView: View {
    @ObservedObject var userPreferences: UserPreferences
    let currentUser: User?
    let size: CGFloat
    let showShadow: Bool

    public init(
        userPreferences: UserPreferences = .shared,
        currentUser: User? = nil,
        size: CGFloat = 42,
        showShadow: Bool = true
    ) {
        self.userPreferences = userPreferences
        self.currentUser = currentUser
        self.size = size
        self.showShadow = showShadow
    }

    private var resolvedName: String {
        if let custom = userPreferences.customDisplayName, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom.trimmingCharacters(in: .whitespaces)
        }
        if let user = currentUser, !user.fullName.trimmingCharacters(in: .whitespaces).isEmpty {
            return user.fullName.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    public var body: some View {
        avatarContent
            .frame(width: size, height: size)
            .if(showShadow) { view in
                view.shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let data = userPreferences.customProfileImageData, let uiImage = UIImage(data: data) {
            // Priority 1A: User's custom photo in memory
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.orbixCardBorder, lineWidth: 1)
                )
        } else if let remoteUrl = userPreferences.remoteProfileImageUrl ?? currentUser?.profileImageUrl,
                  !remoteUrl.isEmpty,
                  let url = resolveURL(remoteUrl) {
            // Priority 1B: User's remote profile photo
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.orbixCardBorder, lineWidth: 1)
                        )
                default:
                    fallbackAvatar
                }
            }
        } else {
            fallbackAvatar
        }
    }

    @ViewBuilder
    private var fallbackAvatar: some View {
        if let emoji = userPreferences.customAvatarEmoji, !emoji.isEmpty {
            // Priority 2: Custom avatar emoji & accent color badge
            let colorHex = userPreferences.customAvatarColorHex ?? "#FFC43D"
            Circle()
                .fill(Color(hex: colorHex).opacity(0.18))
                .overlay(
                    Circle()
                        .stroke(Color(hex: colorHex), lineWidth: 1.5)
                )
                .overlay(
                    Text(emoji)
                        .font(.system(size: size * 0.52))
                )
        } else if !resolvedName.isEmpty {
            // Priority 3: User initials
            let initial = String(resolvedName.prefix(1)).uppercased()
            Circle()
                .fill(Color.lumaSurfaceElevated)
                .overlay(
                    Circle()
                        .stroke(Color.orbixCardBorder, lineWidth: 1)
                )
                .overlay(
                    Text(initial)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundColor(Color.orbixPrimaryText)
                )
        } else {
            // Priority 4: Default silhouette
            Circle()
                .fill(Color.lumaSurface)
                .overlay(
                    Circle()
                        .stroke(Color.orbixCardBorder, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: size * 0.62))
                        .foregroundColor(Color.orbixPrimaryText.opacity(0.8))
                )
        }
    }

    private func resolveURL(_ urlString: String) -> URL? {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return URL(string: urlString)
        }
        let path = urlString.hasPrefix("/") ? String(urlString.dropFirst()) : urlString
        if #available(iOS 16.0, macOS 13.0, *) {
            return APIConfiguration.defaultBaseURL.appending(path: path)
        } else {
            var url = APIConfiguration.defaultBaseURL
            for comp in path.split(separator: "/") {
                url = url.appendingPathComponent(String(comp))
            }
            return url
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
