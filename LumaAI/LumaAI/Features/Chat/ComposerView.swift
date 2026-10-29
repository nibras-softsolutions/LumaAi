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

    public var body: some View {
        VStack(spacing: 8) {
            // Mode Banner if image mode is active
            if isImageMode {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.lumaAccent)
                    Text("Image Generation Mode")
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

            // Attached Photo Preview Strip
            if let img = attachedImage {
                HStack(spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.lumaBorder, lineWidth: 1)
                            )

                        Button(action: {
                            withAnimation(.spring(response: 0.25)) {
                                attachedImage = nil
                                selectedPhotoItem = nil
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.lumaPrimaryText)
                                .background(Circle().fill(Color.white))
                        }
                        .offset(x: 6, y: -6)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Photo Attached")
                            .font(LumaTypography.captionMedium)
                            .foregroundColor(.lumaPrimaryText)
                        Text("Ready to send with your message")
                            .font(LumaTypography.caption)
                            .foregroundColor(.lumaSecondaryText)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.lumaSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Main Input Capsule
            HStack(alignment: .bottom, spacing: 6) {
                // Photo Picker Button
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Color(red: 70/255, green: 65/255, blue: 60/255))
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.04))
                        .clipShape(Circle())
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
                .contextMenu {
                    Button(action: onToggleImageMode) {
                        Label(isImageMode ? "Switch to Text Mode" : "Generate AI Image", systemImage: "sparkles")
                    }
                }

                // Live Camera OCR Text Scanner Button
                Button(action: {
                    HapticFeedback.light()
                    onScanText()
                }) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Color(red: 70/255, green: 65/255, blue: 60/255))
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.04))
                        .clipShape(Circle())
                }

                // Voice Dictation / Recording Button
                Button(action: {
                    HapticFeedback.light()
                    onToggleVoice()
                }) {
                    ZStack {
                        if isDictating {
                            Circle()
                                .fill(Color.lumaError.opacity(0.18))
                                .frame(width: 36, height: 36)
                                .scaleEffect(1.0 + CGFloat(speechAudioLevel) * 0.35)
                                .animation(.easeInOut(duration: 0.12), value: speechAudioLevel)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.lumaError)
                        } else {
                            Circle()
                                .fill(Color.black.opacity(0.04))
                                .frame(width: 36, height: 36)

                            Image(systemName: "mic")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(Color(red: 70/255, green: 65/255, blue: 60/255))
                        }
                    }
                    .frame(width: 36, height: 36)
                }
                .contextMenu {
                    Button(action: onOpenVoiceMode) {
                        Label("Open Voice Conversation Mode", systemImage: "waveform")
                    }
                }

                // High-Contrast Input Field with Crisp Readable Placeholder
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(isImageMode ? "Describe the image to generate…" : "Message Luma AI…")
                            .font(LumaTypography.body)
                            .foregroundColor(Color(red: 120/255, green: 113/255, blue: 108/255)) // Warm gray #78716C (high contrast)
                            .padding(.horizontal, 4)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $text, axis: .vertical)
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
                }

                // Send / Stop Button with Distinct Enabled and Disabled States
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
                                .fill(canSend ? Color.lumaPrimaryText : Color(red: 228/255, green: 226/255, blue: 224/255))
                                .frame(width: 38, height: 38)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(canSend ? Color.white : Color(red: 140/255, green: 135/255, blue: 130/255))
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
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImage != nil) && !isStreaming
    }
}
