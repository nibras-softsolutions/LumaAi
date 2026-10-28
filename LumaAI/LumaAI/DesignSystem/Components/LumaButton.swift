import SwiftUI

public enum LumaButtonStyle {
    case primary
    case secondary
    case destructive
    case ghost
}

public struct LumaButton: View {
    let title: String
    let icon: String?
    let style: LumaButtonStyle
    let isLoading: Bool
    let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        style: LumaButtonStyle = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(title)
                        .font(LumaTypography.bodyMedium)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .disabled(isLoading)
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return .lumaPrimaryText
        case .secondary:
            return .lumaSurfaceElevated
        case .destructive:
            return .lumaError.opacity(0.1)
        case .ghost:
            return .clear
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return .lumaPrimaryText
        case .destructive:
            return .lumaError
        case .ghost:
            return .lumaPrimaryText
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            return .clear
        case .secondary:
            return .lumaBorder
        case .destructive:
            return .lumaError.opacity(0.2)
        case .ghost:
            return .clear
        }
    }
}
