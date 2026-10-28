import SwiftUI

public struct VoiceConversationView: View {
    @ObservedObject var viewModel: VoiceViewModel
    let onDismiss: () -> Void

    public init(viewModel: VoiceViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.lumaCanvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 8, height: 8)

                        Text(statusLabel)
                            .font(LumaTypography.headline)
                            .foregroundColor(.lumaPrimaryText)
                    }

                    Spacer()

                    // Replay button
                    if !viewModel.lastSpokenText.isEmpty {
                        Button(action: {
                            HapticFeedback.light()
                            viewModel.replayLastResponse()
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 16))
                                .foregroundColor(.lumaPrimaryText)
                                .frame(width: 38, height: 38)
                                .background(Color.lumaSurfaceElevated)
                                .clipShape(Circle())
                        }
                    }

                    // Mute / Unmute Button
                    Button(action: {
                        HapticFeedback.light()
                        viewModel.toggleMute()
                    }) {
                        Image(systemName: viewModel.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 16))
                            .foregroundColor(viewModel.isMuted ? .lumaError : .lumaPrimaryText)
                            .frame(width: 38, height: 38)
                            .background(Color.lumaSurfaceElevated)
                            .clipShape(Circle())
                    }

                    // Close Button
                    Button(action: {
                        HapticFeedback.light()
                        viewModel.stopSession()
                        onDismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.lumaPrimaryText)
                            .frame(width: 38, height: 38)
                            .background(Color.lumaSurfaceElevated)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // Center Animated Visualizer Orb
                AudioVisualizerView(
                    state: viewModel.state,
                    audioLevel: viewModel.speechService.audioLevel,
                    onTap: {
                        viewModel.handleOrbTap()
                    }
                )

                Spacer()

                // Transcripts
                VStack(spacing: 12) {
                    Text(viewModel.userTranscript)
                        .font(LumaTypography.title)
                        .foregroundColor(.lumaPrimaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 32)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.userTranscript)

                    if !viewModel.assistantTranscript.isEmpty {
                        Text(viewModel.assistantTranscript)
                            .font(LumaTypography.body)
                            .foregroundColor(.lumaSecondaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .padding(.horizontal, 32)
                            .animation(.easeInOut(duration: 0.2), value: viewModel.assistantTranscript)
                    }
                }
                .frame(minHeight: 110)

                Spacer()

                // Bottom Hint Pill
                Button(action: {
                    viewModel.handleOrbTap()
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 6, height: 6)
                        Text(actionHint)
                            .font(LumaTypography.subheadline)
                            .foregroundColor(.lumaPrimaryText)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.lumaSurface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.lumaBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 36)
            }
        }
        .task {
            await viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }

    private var statusDotColor: Color {
        switch viewModel.state {
        case .listening:
            return .lumaAccent
        case .thinking:
            return Color(red: 168/255, green: 85/255, blue: 247/255)
        case .speaking:
            return .lumaSuccess
        case .muted:
            return .lumaError
        }
    }

    private var statusLabel: String {
        switch viewModel.state {
        case .listening:
            return "Listening…"
        case .thinking:
            return "Thinking…"
        case .speaking:
            return "Speaking…"
        case .muted:
            return "Muted"
        }
    }

    private var actionHint: String {
        switch viewModel.state {
        case .listening:
            return "Tap orb to send immediately"
        case .thinking:
            return "Thinking…"
        case .speaking:
            return "Tap orb to interrupt"
        case .muted:
            return "Tap to unmute"
        }
    }
}
