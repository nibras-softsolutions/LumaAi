import SwiftUI

public struct LumaTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let errorMessage: String?

    @State private var isPasswordVisible: Bool = false

    public init(
        _ title: String,
        placeholder: String = "",
        text: Binding<String>,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        errorMessage: String? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.errorMessage = errorMessage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(LumaTypography.subheadline)
                .foregroundColor(.lumaSecondaryText)

            HStack {
                if isSecure && !isPasswordVisible {
                    SecureField(placeholder, text: $text)
                        .font(LumaTypography.body)
                        .textContentType(textContentType)
                } else {
                    TextField(placeholder, text: $text)
                        .font(LumaTypography.body)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .autocapitalization(keyboardType == .emailAddress ? .none : .words)
                        .disableAutocorrection(keyboardType == .emailAddress)
                }

                if isSecure {
                    Button(action: { isPasswordVisible.toggle() }) {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .font(.system(size: 15))
                            .foregroundColor(.lumaTertiaryText)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.lumaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(errorMessage != nil ? Color.lumaError : Color.lumaBorder, lineWidth: 1)
            )

            if let error = errorMessage {
                Text(error)
                    .font(LumaTypography.caption)
                    .foregroundColor(.lumaError)
                    .padding(.horizontal, 4)
            }
        }
    }
}
