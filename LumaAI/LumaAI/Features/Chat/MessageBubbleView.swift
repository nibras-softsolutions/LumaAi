import SwiftUI

public struct MessageBubbleView: View {
    let message: ChatMessage
    let onImageTapped: ((ImageAttachment) -> Void)?

    @State private var showCopiedAlert: Bool = false

    public init(message: ChatMessage, onImageTapped: ((ImageAttachment) -> Void)? = nil) {
        self.message = message
        self.onImageTapped = onImageTapped
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                assistantAvatar
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Image Attachment if present
                if let attachment = message.imageAttachment {
                    imageCard(attachment)
                }

                // Text Bubble
                if !message.content.isEmpty {
                    bubbleContent
                } else if message.status == .streaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Thinking…")
                            .font(LumaTypography.subheadline)
                            .foregroundColor(.lumaSecondaryText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.lumaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.lumaBorder, lineWidth: 1)
                    )
                }

                // Error message banner
                if let err = message.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.lumaError)
                        Text(err)
                            .font(LumaTypography.caption)
                            .foregroundColor(.lumaError)
                    }
                    .padding(.horizontal, 8)
                }

                // Bubble actions (Copy button on long press or context menu)
                if message.role == .assistant && message.status == .complete && !message.content.isEmpty {
                    Button(action: {
                        UIPasteboard.general.string = message.content
                        HapticFeedback.light()
                        withAnimation {
                            showCopiedAlert = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                showCopiedAlert = false
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                            Text(showCopiedAlert ? "Copied" : "Copy")
                        }
                        .font(LumaTypography.caption)
                        .foregroundColor(showCopiedAlert ? .lumaSuccess : .lumaTertiaryText)
                    }
                    .padding(.horizontal, 4)
                }
            }

            if message.role == .user {
                // User aligns to trailing
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var assistantAvatar: some View {
        Circle()
            .fill(Color.lumaSurfaceElevated)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.lumaPrimaryText)
            )
            .padding(.top, 2)
    }

    private var bubbleContent: some View {
        Group {
            if message.role == .user {
                Text(message.content)
                    .font(LumaTypography.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.lumaPrimaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                MarkdownView(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.lumaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.lumaBorder, lineWidth: 1)
                    )
            }
        }
        .contextMenu {
            Button(action: {
                UIPasteboard.general.string = message.content
                HapticFeedback.light()
            }) {
                Label("Copy Message", systemImage: "doc.on.doc")
            }
        }
    }

    private func imageCard(_ attachment: ImageAttachment) -> some View {
        Button(action: {
            onImageTapped?(attachment)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: attachment.imageUrl.hasPrefix("http") ? attachment.imageUrl : "https://lumaai-j0u3.onrender.com" + attachment.imageUrl)) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color.lumaSurfaceElevated
                            ProgressView()
                        }
                        .frame(width: 260, height: 260)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 260, height: 260)
                            .clipped()
                    case .failure:
                        ZStack {
                            Color.lumaSurfaceElevated
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 30))
                                    .foregroundColor(.lumaTertiaryText)
                                Text("Could not load image")
                                    .font(LumaTypography.caption)
                                    .foregroundColor(.lumaSecondaryText)
                            }
                        }
                        .frame(width: 260, height: 260)
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack {
                    Text(attachment.prompt)
                        .font(LumaTypography.caption)
                        .foregroundColor(.lumaSecondaryText)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "arrow.up.right.and.arrow.down.left.rectangle")
                        .font(.system(size: 13))
                        .foregroundColor(.lumaTertiaryText)
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .background(Color.lumaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.lumaBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
