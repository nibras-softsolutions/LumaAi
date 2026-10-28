import SwiftUI

public struct ImageGenerationView: View {
    @StateObject private var viewModel: ImageGenerationViewModel
    @State private var selectedAttachmentForViewer: ImageAttachment?

    public init(apiClient: APIClientProtocol) {
        _viewModel = StateObject(wrappedValue: ImageGenerationViewModel(apiClient: apiClient))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.lumaCanvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Prompt Input Section
                        promptSection

                        // Aspect Ratio Selector
                        aspectRatioSection

                        // Generate Button
                        generateButton

                        // Error State if any
                        if let error = viewModel.errorMessage {
                            errorMessageView(error)
                        }

                        // Generation Result or Placeholder
                        resultSection

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Imagine")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedAttachmentForViewer) { attachment in
                ImageViewerView(attachment: attachment)
            }
        }
    }

    // MARK: - Subviews

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROMPT")
                .font(LumaTypography.caption)
                .foregroundColor(.lumaSecondaryText)

            TextEditor(text: $viewModel.prompt)
                .font(LumaTypography.body)
                .foregroundColor(.lumaPrimaryText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100, maxHeight: 150)
                .padding(12)
                .background(Color.lumaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.lumaBorder, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.prompt.isEmpty {
                        Text("Describe what you want to see in rich detail…")
                            .font(LumaTypography.body)
                            .foregroundColor(.lumaTertiaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var aspectRatioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASPECT RATIO")
                .font(LumaTypography.caption)
                .foregroundColor(.lumaSecondaryText)

            HStack(spacing: 10) {
                ForEach(viewModel.aspectRatios, id: \.id) { ratio in
                    let isSelected = viewModel.selectedAspectRatio == ratio.id
                    Button(action: {
                        HapticFeedback.selection()
                        viewModel.selectedAspectRatio = ratio.id
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: ratio.icon)
                                .font(.system(size: 18))
                                .foregroundColor(isSelected ? .white : .lumaPrimaryText)

                            Text(ratio.id)
                                .font(LumaTypography.caption)
                                .foregroundColor(isSelected ? .white : .lumaSecondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isSelected ? Color.lumaPrimaryText : Color.lumaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? Color.clear : Color.lumaBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var generateButton: some View {
        let isPromptEmpty = viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return LumaButton(
            viewModel.isGenerating ? "Synthesizing…" : "Generate Artwork",
            style: .primary,
            isLoading: viewModel.isGenerating
        ) {
            HapticFeedback.medium()
            Task {
                await viewModel.generate()
            }
        }
        .disabled(isPromptEmpty || viewModel.isGenerating)
        .opacity(isPromptEmpty ? 0.5 : 1.0)
    }

    private func errorMessageView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.lumaError)
            Text(message)
                .font(LumaTypography.caption)
                .foregroundColor(.lumaError)
            Spacer()
        }
        .padding(14)
        .background(Color.lumaError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = viewModel.generatedImage {
                Text("RESULT")
                    .font(LumaTypography.caption)
                    .foregroundColor(.lumaSecondaryText)

                let fullUrlString = image.imageUrl.hasPrefix("http") ? image.imageUrl : "https://lumaai-j0u3.onrender.com" + image.imageUrl

                AsyncImage(url: URL(string: fullUrlString)) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.lumaSurface)
                            .frame(height: 300)
                            .overlay(
                                ProgressView()
                                    .tint(.lumaSecondaryText)
                            )
                    case .success(let loaded):
                        loaded
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.lumaBorder, lineWidth: 1)
                            )
                            .onTapGesture {
                                HapticFeedback.light()
                                selectedAttachmentForViewer = ImageAttachment(
                                    id: image.id,
                                    prompt: image.prompt,
                                    aspectRatio: image.aspectRatio,
                                    imageUrl: image.imageUrl,
                                    width: image.width,
                                    height: image.height,
                                    provider: image.provider,
                                    model: image.model
                                )
                            }
                    case .failure:
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.lumaSurface)
                            .frame(height: 240)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .font(.system(size: 28))
                                        .foregroundColor(.lumaError)
                                    Text("Failed to render preview")
                                        .font(LumaTypography.caption)
                                        .foregroundColor(.lumaSecondaryText)
                                }
                            )
                    @unknown default:
                        EmptyView()
                    }
                }

                HStack {
                    Text("\(image.provider) · \(image.model) · \(image.aspectRatio)")
                        .font(LumaTypography.caption)
                        .foregroundColor(.lumaTertiaryText)

                    Spacer()

                    Button(action: {
                        selectedAttachmentForViewer = ImageAttachment(
                            id: image.id,
                            prompt: image.prompt,
                            aspectRatio: image.aspectRatio,
                            imageUrl: image.imageUrl,
                            width: image.width,
                            height: image.height,
                            provider: image.provider,
                            model: image.model
                        )
                    }) {
                        HStack(spacing: 4) {
                            Text("Inspect")
                            Image(systemName: "arrow.up.right.and.arrow.down.left.rectangle")
                        }
                        .font(LumaTypography.caption)
                        .foregroundColor(.lumaAccent)
                    }
                }
            } else if viewModel.isGenerating {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.lumaSurface)
                    .frame(height: 280)
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.lumaAccent)
                                .scaleEffect(1.2)

                            Text("Rendering artwork with Pollinations FLUX…")
                                .font(LumaTypography.subheadline)
                                .foregroundColor(.lumaSecondaryText)
                        }
                    )
            }
        }
    }
}
