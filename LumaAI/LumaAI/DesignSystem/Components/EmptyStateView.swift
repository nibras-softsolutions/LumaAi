import SwiftUI

public struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.lumaSurfaceElevated)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundColor(.lumaPrimaryText)
                )

            VStack(spacing: 6) {
                Text(title)
                    .font(LumaTypography.headline)
                    .foregroundColor(.lumaPrimaryText)

                Text(message)
                    .font(LumaTypography.subheadline)
                    .foregroundColor(.lumaSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: {
                    HapticFeedback.light()
                    action()
                }) {
                    Text(actionTitle)
                        .font(LumaTypography.bodyMedium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.lumaPrimaryText)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
