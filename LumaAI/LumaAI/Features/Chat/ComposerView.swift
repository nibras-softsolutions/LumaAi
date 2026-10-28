import SwiftUI

public struct ComposerView: View {
    @Binding var text: String
    let isStreaming: Bool
    let isImageMode: Bool
    let onToggleImageMode: () -> Void
    let onScanText: () -> Void
    let onStartVoice: () -> Void
    let onSend: () -> Void
    let onStop: () -> Void
    var onFocusChange: ((Bool) -> Void)?

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        isStreaming: Bool,
        isImageMode: Bool,
        onToggleImageMode: @escaping () -> Void,
        onScanText: @escaping () -> Void,
        onStartVoice: @escaping () -> Void,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self._text = text
        self.isStreaming = isStreaming
        self.isImageMode = isImageMode
        self.onToggleImageMode = onToggleImageMode
        self.onScanText = onScanText
        self.onStartVoice = onStartVoice
        self.onSend = onSend
        self.onStop = onStop
        self.onFocusChange = onFocusChange
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Mode Banner if image mode is active
            if isImageMode {
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 13))
                        .foregroundColor(.lumaAccent)
                    Text("Image Generation Mode active")
                        .font(LumaTypography.captionMedium)
                        .foregroundColor(.lumaAccent)
                    Spacer()
                    Button(action: onToggleImageMode) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.lumaSecondaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.lumaAccentLight)
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Input Bar
            HStack(alignment: .bottom, spacing: 8) {
                // Image Mode Toggle Button
                Button(action: {
                    HapticFeedback.selection()
                    onToggleImageMode()
                }) {
                    Image(systemName: isImageMode ? "photo.fill" : "photo")
                        .font(.system(size: 17))
                        .foregroundColor(isImageMode ? .lumaAccent : .lumaSecondaryText)
                        .frame(width: 36, height: 36)
                        .background(isImageMode ? Color.lumaAccentLight : Color.clear)
                        .clipShape(Circle())
                }

                // Live Camera OCR Text Scanner Button
                Button(action: {
                    HapticFeedback.light()
                    onScanText()
                }) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 17))
                        .foregroundColor(.lumaSecondaryText)
                        .frame(width: 36, height: 36)
                        .background(Color.clear)
                        .clipShape(Circle())
                }

                // Voice Conversation Mode Button
                Button(action: {
                    HapticFeedback.light()
                    onStartVoice()
                }) {
                    Image(systemName: "waveform")
                        .font(.system(size: 17))
                        .foregroundColor(.lumaSecondaryText)
                        .frame(width: 36, height: 36)
                        .background(Color.clear)
                        .clipShape(Circle())
                }

                // Multiline Text Field
                TextField(
                    isImageMode ? "Describe the image to generate…" : "Message Luma AI…",
                    text: $text,
                    axis: .vertical
                )
                .font(LumaTypography.body)
                .foregroundColor(.lumaPrimaryText)
                .focused($isFocused)
                .lineLimit(1...5)
                .frame(minHeight: 38)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .onChange(of: isFocused) { focused in
                    onFocusChange?(focused)
                }

                // Send / Stop Button
                if isStreaming {
                    Button(action: {
                        HapticFeedback.medium()
                        onStop()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.lumaPrimaryText)
                                .frame(width: 38, height: 38)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white)
                                .frame(width: 12, height: 12)
                        }
                    }
                } else {
                    Button(action: {
                        guard canSend else { return }
                        HapticFeedback.light()
                        onSend()
                    }) {
                        ZStack {
                            Circle()
                                .fill(canSend ? Color.lumaPrimaryText : Color.lumaBorder)
                                .frame(width: 38, height: 38)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(canSend ? .white : .lumaTertiaryText)
                        }
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.lumaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.lumaBorder, lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.lumaCanvas)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }
}
