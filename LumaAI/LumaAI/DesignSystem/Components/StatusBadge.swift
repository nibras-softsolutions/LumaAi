import SwiftUI

public enum BadgeStatus {
    case online
    case checking
    case offline
    case error
}

public struct StatusBadge: View {
    let title: String
    let status: BadgeStatus

    public init(_ title: String, status: BadgeStatus) {
        self.title = title
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(title)
                .font(LumaTypography.captionMedium)
                .foregroundColor(.lumaSecondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.lumaSurfaceElevated)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.lumaBorder, lineWidth: 0.5)
        )
    }

    private var statusColor: Color {
        switch status {
        case .online:
            return .lumaSuccess
        case .checking:
            return .lumaWarning
        case .offline, .error:
            return .lumaError
        }
    }
}
