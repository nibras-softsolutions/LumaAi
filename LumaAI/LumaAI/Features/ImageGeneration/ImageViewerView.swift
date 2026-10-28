import SwiftUI
import UIKit

public struct ImageViewerView: View {
    let attachment: ImageAttachment
    @Environment(\.dismiss) private var dismiss

    @State private var loadedImage: UIImage?
    @State private var isDownloading: Bool = true
    @State private var isSaved: Bool = false
    @State private var errorMessage: String?
    @State private var isSharing: Bool = false

    public init(attachment: ImageAttachment) {
        self.attachment = attachment
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    if let image = loadedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                    } else if isDownloading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.6))
                            Text(errorMessage ?? "Could not load image")
                                .font(LumaTypography.body)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }

                    Spacer()

                    // Bottom info card
                    VStack(alignment: .leading, spacing: 8) {
                        Text(attachment.prompt)
                            .font(LumaTypography.body)
                            .foregroundColor(.white)
                            .lineLimit(3)

                        HStack {
                            Text("\(attachment.provider) · \(attachment.model) · \(attachment.aspectRatio)")
                                .font(LumaTypography.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                        }
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if let image = loadedImage {
                        Button(action: {
                            HapticFeedback.light()
                            isSharing = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.white)
                        }

                        Button(action: {
                            saveToPhotos(image)
                        }) {
                            Image(systemName: isSaved ? "checkmark" : "arrow.down.to.line")
                                .foregroundColor(isSaved ? .lumaSuccess : .white)
                        }
                    }
                }
            }
            .sheet(isPresented: $isSharing) {
                if let image = loadedImage {
                    ShareSheet(items: [image, attachment.prompt])
                }
            }
            .task {
                await loadImage()
            }
        }
    }

    private func loadImage() async {
        isDownloading = true
        errorMessage = nil

        let urlString = attachment.imageUrl.hasPrefix("http") ? attachment.imageUrl : "https://lumaai-j0u3.onrender.com" + attachment.imageUrl
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid image URL"
            isDownloading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let uiImage = UIImage(data: data) {
                self.loadedImage = uiImage
            } else {
                errorMessage = "Invalid image data"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isDownloading = false
    }

    private func saveToPhotos(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        HapticFeedback.success()
        withAnimation {
            isSaved = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isSaved = false
            }
        }
    }
}

public struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
