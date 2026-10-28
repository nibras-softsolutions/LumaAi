import SwiftUI

public enum VoiceState {
    case listening
    case thinking
    case speaking
    case muted
}

public struct AudioVisualizerView: View {
    let state: VoiceState
    let audioLevel: Float
    let onTap: () -> Void

    @State private var waveAnimation: Bool = false

    public init(state: VoiceState, audioLevel: Float = 0.0, onTap: @escaping () -> Void) {
        self.state = state
        self.audioLevel = audioLevel
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: {
            HapticFeedback.medium()
            onTap()
        }) {
            ZStack {
                // Outer Ripple Ring 3
                Circle()
                    .stroke(orbColor.opacity(ringOpacity(0.12)), lineWidth: 1.5)
                    .frame(width: baseSize + (waveAnimation ? 90 : 20) + CGFloat(audioLevel * 40))
                    .animation(ringAnimation(duration: 2.2, delay: 0.6), value: waveAnimation)

                // Middle Ripple Ring 2
                Circle()
                    .stroke(orbColor.opacity(ringOpacity(0.2)), lineWidth: 2)
                    .frame(width: baseSize + (waveAnimation ? 50 : 10) + CGFloat(audioLevel * 30))
                    .animation(ringAnimation(duration: 1.8, delay: 0.3), value: waveAnimation)

                // Inner Ripple Ring 1
                Circle()
                    .stroke(orbColor.opacity(ringOpacity(0.35)), lineWidth: 2.5)
                    .frame(width: baseSize + (waveAnimation ? 20 : 0) + CGFloat(audioLevel * 20))
                    .animation(ringAnimation(duration: 1.4, delay: 0), value: waveAnimation)

                // Core Orb Surface
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                orbColor.opacity(0.9),
                                orbColor.opacity(0.7)
                            ]),
                            center: .center,
                            startRadius: 5,
                            endRadius: baseSize / 2
                        )
                    )
                    .frame(width: baseSize, height: baseSize)
                    .shadow(color: orbColor.opacity(0.3), radius: 20, x: 0, y: 8)
                    .overlay(
                        // Inner icon / sparkle indicator
                        Image(systemName: iconName)
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(.white)
                            .scaleEffect(waveAnimation ? 1.05 : 0.95)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: waveAnimation)
                    )
            }
            .frame(width: 260, height: 260)
        }
        .buttonStyle(.plain)
        .onAppear {
            waveAnimation = true
        }
    }

    private var baseSize: CGFloat { 110 }

    private var orbColor: Color {
        switch state {
        case .listening:
            return .lumaAccent
        case .thinking:
            return Color(red: 168/255, green: 85/255, blue: 247/255) // Purple tone
        case .speaking:
            return .lumaPrimaryText
        case .muted:
            return .lumaTertiaryText
        }
    }

    private var iconName: String {
        switch state {
        case .listening:
            return "mic.fill"
        case .thinking:
            return "ellipsis"
        case .speaking:
            return "waveform"
        case .muted:
            return "mic.slash.fill"
        }
    }

    private func ringOpacity(_ base: Double) -> Double {
        switch state {
        case .listening, .speaking:
            return base + Double(audioLevel * 0.3)
        case .thinking:
            return base * 0.7
        case .muted:
            return 0.05
        }
    }

    private func ringAnimation(duration: Double, delay: Double) -> Animation {
        Animation.easeInOut(duration: duration)
            .repeatForever(autoreverses: true)
            .delay(delay)
    }
}
