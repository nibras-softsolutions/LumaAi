import SwiftUI
import PhotosUI

public struct ComposerView: View {
    @Binding var text: String
    @Binding var attachedImage: UIImage?
    let isStreaming: Bool
    let isImageMode: Bool
    let isDictating: Bool
    let speechAudioLevel: Float
    let onToggleImageMode: () -> Void
    let onScanText: () -> Void
    let onToggleVoice: () -> Void
    let onOpenVoiceMode: () -> Void
    let onSend: () -> Void
    let onStop: () -> Void
    var onFocusChange: ((Bool) -> Void)?

    @FocusState private var isFocused: Bool
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    public init(
        text: Binding<String>,
        attachedImage: Binding<UIImage?> = .constant(nil),
        isStreaming: Bool,
        isImageMode: Bool,
        isDictating: Bool = false,
        speechAudioLevel: Float = 0.0,
        onToggleImageMode: @escaping () -> Void,
        onScanText: @escaping () -> Void,
        onToggleVoice: @escaping () -> Void,
        onOpenVoiceMode: @escaping () -> Void,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self._text = text
        self._attachedImage = attachedImage
        self.isStreaming = isStreaming
        self.isImageMode = isImageMode
        self.isDictating = isDictating
        self.speechAudioLevel = speechAudioLevel
        self.onToggleImageMode = onToggleImageMode
        self.onScanText = onScanText
        self.onToggleVoice = onToggleVoice
        self.onOpenVoiceMode = onOpenVoiceMode
        self.onSend = onSend
        self.onStop = onStop
        self.onFocusChange = onFocusChange
    }

    private var hasInput: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImage != nil
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Mode Banner if image mode is active
            if isImageMode {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.orbixPurple)
                    Text("Image Generation Mode")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.orbixPurple)
                    Spacer()
                    Button(action: onToggleImageMode) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.orbixSecondaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.orbixLavender.opacity(0.45))
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Attached Photo Preview Strip
            if let img = attachedImage {
                HStack(spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.orbixCardBorder, lineWidth: 1)
                            )

                        Button(action: {
                            withAnimation(.spring(response: 0.25)) {
                                attachedImage = nil
                                selectedPhotoItem = nil
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color.orbixPrimaryText)
                                .background(Circle().fill(Color.white))
                        }
                        .offset(x: 6, y: -6)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Photo Attached")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.orbixPrimaryText)
                        Text("Ready to analyze with your message")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color.orbixSecondaryText)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.orbixCardBorder, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Orbix Studio White Input Capsule / Card
            HStack(alignment: .center, spacing: 8) {
                // Camera / OCR Scan Button (Left icon matching reference)
                Button(action: {
                    HapticFeedback.light()
                    onScanText()
                }) {
                    Image(systemName: "camera")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Color.orbixSecondaryText)
                        .frame(width: 38, height: 38)
                        .background(Color.orbixBackground)
                        .clipShape(Circle())
                }
                .contextMenu {
                    Button(action: onScanText) {
                        Label("Scan Text with Camera", systemImage: "text.viewfinder")
                    }
                    Button(action: onToggleImageMode) {
                        Label(isImageMode ? "Switch to Text Mode" : "Generate AI Image", systemImage: "sparkles")
                    }
                }

                // Photos Picker Button
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Color.orbixSecondaryText)
                        .frame(width: 32, height: 32)
                }
                .onChange(of: selectedPhotoItem) { newItem in
                    guard let item = newItem else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            await MainActor.run {
                                withAnimation(.spring(response: 0.25)) {
                                    self.attachedImage = uiImage
                                }
                            }
                        }
                    }
                }

                // Center Text Input with High Contrast Placeholder ("Ask Anything...")
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(isImageMode ? "Describe image to create…" : "Ask Anything…")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(Color.orbixSecondaryText.opacity(0.85))
                            .padding(.horizontal, 4)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $text, axis: .vertical)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color.orbixPrimaryText)
                        .focused($isFocused)
                        .lineLimit(1...5)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .onChange(of: isFocused) { focused in
                            onFocusChange?(focused)
                        }
                }

                // Action Controls on Right
                if isStreaming {
                    // Stop Button
                    Button(action: {
                        HapticFeedback.medium()
                        onStop()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.orbixBlackPill)
                                .frame(width: 40, height: 40)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white)
                                .frame(width: 12, height: 12)
                        }
                    }
                } else if hasInput {
                    // Active Send Button
                    Button(action: {
                        HapticFeedback.medium()
                        onSend()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.orbixBlackPill)
                                .frame(width: 40, height: 40)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Orbix Studio Purple Circular Audio Waveform Button (#8765F5) - Enters Voice Assistant Mode
                    Button(action: {
                        HapticFeedback.medium()
                        onOpenVoiceMode()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.orbixPurple)
                                .frame(width: 40, height: 40)

                            if isDictating {
                                Circle()
                                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                                    .frame(width: 40, height: 40)
                                    .scaleEffect(1.0 + CGFloat(speechAudioLevel) * 0.3)
                                    .animation(.easeInOut(duration: 0.12), value: speechAudioLevel)

                                Image(systemName: "waveform")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "waveform")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .contentShape(Circle())
                        .shadow(color: Color.orbixPurple.opacity(0.35), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Enter voice assistant mode")
                    .contextMenu {
                        Button(action: onOpenVoiceMode) {
                            Label("Voice Assistant Mode", systemImage: "waveform.circle.fill")
                        }
                        Button(action: onToggleVoice) {
                            Label(isDictating ? "Stop Dictation" : "Dictate into Text", systemImage: "mic.fill")
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.orbixCardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 4)
    }
}
