import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var preferences: UserPreferences
    let onFinished: () -> Void

    @State private var currentPage: Int = 0
    @State private var appeared: Bool = false

    public init(
        preferences: UserPreferences = .shared,
        onFinished: @escaping () -> Void = {}
    ) {
        self.preferences = preferences
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            // Orbix Studio Lavender-tinted background with angled soft gradient
            OrbixBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack(alignment: .center) {
                    if currentPage > 0 {
                        Button(action: {
                            HapticFeedback.light()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentPage -= 1
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundColor(Color.orbixPrimaryText)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.lumaSurface.opacity(0.85))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.orbixCardBorder, lineWidth: 1)
                            )
                        }
                        .transition(.opacity.combined(with: .scale))
                    } else {
                        // Branding mark on Page 1
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.orbixPurple)
                                    .frame(width: 28, height: 28)
                                Image(systemName: "sparkle")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            Text("Luma AI")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(Color.orbixPrimaryText)
                        }
                    }

                    Spacer()

                    // Skip Button
                    Button(action: {
                        HapticFeedback.light()
                        completeOnboarding()
                    }) {
                        Text("Skip")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.orbixSecondaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.lumaSurface.opacity(0.85))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.orbixCardBorder, lineWidth: 1)
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 6)

                // 3 Animated Onboarding Pages
                TabView(selection: $currentPage) {
                    onboardingPageOne
                        .tag(0)

                    onboardingPageTwo
                        .tag(1)

                    onboardingPageThree
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Bottom Controls matching Orbix Studio
                VStack(spacing: 20) {
                    // 3-Dot Animated Page Indicator
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(currentPage == index ? Color.orbixPrimaryText : Color.orbixSecondaryText.opacity(0.25))
                                .frame(width: currentPage == index ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPage)
                        }
                    }

                    // High-contrast Black Pill Primary Button
                    Button(action: {
                        HapticFeedback.light()
                        if currentPage < 2 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentPage += 1
                            }
                        } else {
                            completeOnboarding()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Text(currentPage == 2 ? "Get Started" : "Next")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.orbixBlackPill)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(PillPressStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    // MARK: - Page 1: Meet Your AI Companion
    private var onboardingPageOne: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 10)

            // Smartphone Mockup & Floating Cards Composition
            ZStack {
                // Background Soft Lavender Glow
                Circle()
                    .fill(Color.orbixLavender.opacity(0.6))
                    .frame(width: 260, height: 260)
                    .blur(radius: 40)

                // Smartphone Device Frame Mockup
                VStack(spacing: 0) {
                    // Dynamic Island pill
                    Capsule()
                        .fill(Color.black)
                        .frame(width: 72, height: 20)
                        .padding(.top, 10)

                    // Mockup Screen Content
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.orbixPurple)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: "sparkle")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                    )
                            Text("Luma Intelligence")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.orbixPrimaryText)
                            Spacer()
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                        .padding(.top, 8)

                        // Sample User Query
                        HStack {
                            Spacer()
                            Text("How can AI help me build faster?")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.orbixBlackPill)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        // Sample AI Response
                        HStack(alignment: .top, spacing: 6) {
                            Text("By automating routine boilerplate, debugging complex logic, and sparking creative clarity in seconds.")
                                .font(.system(size: 10.5, weight: .regular))
                                .foregroundColor(Color.orbixPrimaryText)
                                .padding(10)
                                .background(Color.lumaSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)

                    Spacer()
                }
                .frame(width: 210, height: 230)
                .background(Color.lumaSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.orbixCardBorder, lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.09), radius: 20, x: 0, y: 10)

                // Floating Card 1: Conversational AI (Top Right)
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.orbixPurple)
                    Text("Thoughtful Chat")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Color.orbixPrimaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.lumaSurface)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
                .offset(x: 75, y: -90)

                // Floating Card 2: Real-time Voice (Bottom Left)
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.orbixPurple)
                    Text("Natural Voice")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Color.orbixPrimaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.lumaSurface)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
                .offset(x: -75, y: 85)
            }
            .frame(height: 290)

            Spacer(minLength: 10)

            // Text Block matching Orbix Studio typography
            VStack(spacing: 10) {
                Text("Meet Your AI Companion")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Color.orbixPrimaryText)
                    .multilineTextAlignment(.center)

                Text("A smarter space to think, create, and explore.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color.orbixSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 28)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Page 2: Ideas Into Conversations
    private var onboardingPageTwo: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 10)

            // Chat Interface Preview with Message Bubbles & Sparkles
            ZStack {
                // Soft Glow
                Circle()
                    .fill(Color.orbixLavender.opacity(0.55))
                    .frame(width: 250, height: 250)
                    .blur(radius: 35)

                VStack(spacing: 14) {
                    // User Bubble
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("What is the core idea of relativity?")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.orbixBlackPill)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(.leading, 40)

                    // Assistant Card
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.orbixPurple)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "sparkle")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Einstein showed that space and time are not fixed; they stretch and bend with mass and acceleration.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color.orbixPrimaryText)
                                .lineSpacing(3)

                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                                Text("Synthesized with clarity")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(Color.orbixSecondaryText)
                            }
                            .padding(.top, 2)
                        }
                        .padding(14)
                        .background(Color.lumaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.orbixCardBorder, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
                    }
                    .padding(.trailing, 20)

                    // Prompt suggestion chips row
                    HStack(spacing: 8) {
                        chipBadge(title: "Deep Dive", icon: "arrow.right.circle")
                        chipBadge(title: "Provide Example", icon: "lightbulb")
                        chipBadge(title: "Audio Readout", icon: "speaker.wave.2")
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 340)

                // Floating Sparkle Badge (Top Right)
                ZStack {
                    Circle()
                        .fill(Color.lumaSurface)
                        .frame(width: 44, height: 44)
                        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.orbixPurple)
                }
                .offset(x: 135, y: -105)
            }
            .frame(height: 290)

            Spacer(minLength: 10)

            // Text Block
            VStack(spacing: 10) {
                Text("Ideas Into Conversations")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Color.orbixPrimaryText)
                    .multilineTextAlignment(.center)

                Text("Ask questions, solve problems, and explore complex topics.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color.orbixSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 28)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Page 3: Bring Your Imagination to Life
    private var onboardingPageThree: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 10)

            // AI Artwork Preview & Floating Cards
            ZStack {
                // Ambient Glow
                Circle()
                    .fill(Color.orbixLavender.opacity(0.65))
                    .frame(width: 270, height: 270)
                    .blur(radius: 40)

                // Central Main Artwork Preview Card
                ZStack(alignment: .bottomLeading) {
                    // Generative Gradient Visual Art
                    LinearGradient(
                        colors: [
                            Color(red: 35/255, green: 25/255, blue: 60/255),
                            Color(red: 135/255, green: 101/255, blue: 245/255),
                            Color(red: 255/255, green: 175/255, blue: 189/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "sparkles")
                                    .font(.system(size: 24, weight: .light))
                                    .foregroundColor(.white.opacity(0.75))
                                    .padding(16)
                            }
                            Spacer()
                        }
                    )

                    // Bottom artwork label
                    HStack(spacing: 8) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Text("Cosmic Twilight — Generated")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
                    .padding(12)
                }
                .frame(width: 230, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.orbixCardBorder, lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 10)

                // Floating Prompt Card (Top Left)
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.orbixPurple)
                    Text("Serene neon sanctuary")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.orbixPrimaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.lumaSurface)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
                .offset(x: -75, y: -95)

                // Floating Style Pill (Bottom Right)
                HStack(spacing: 6) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 12))
                        .foregroundColor(Color.orbixPurple)
                    Text("Ultra-HD 8K")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.orbixPrimaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.lumaSurface)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
                .offset(x: 75, y: 95)
            }
            .frame(height: 290)

            Spacer(minLength: 10)

            // Text Block
            VStack(spacing: 10) {
                Text("Bring Your Imagination to Life")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Color.orbixPrimaryText)
                    .multilineTextAlignment(.center)

                Text("Turn your ideas into images and discover new creative possibilities.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color.orbixSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 28)
            }
            .padding(.bottom, 20)
        }
    }

    private func chipBadge(title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(Color.orbixSecondaryText)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.orbixSecondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.lumaSurface)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.orbixCardBorder, lineWidth: 1)
        )
    }

    private func completeOnboarding() {
        HapticFeedback.medium()
        preferences.hasCompletedOnboarding = true
        UserPreferences.shared.hasCompletedOnboarding = true
        onFinished()
    }
}

// MARK: - Orbix Studio Background View
public struct OrbixBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            // Crisp Canvas
            Color.orbixBackground

            // Angled soft lavender diagonal band (matches the Orbix Studio reference backdrop)
            GeometryReader { proxy in
                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width * 0.45, y: 0))
                    path.addLine(to: CGPoint(x: proxy.size.width * 1.25, y: 0))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.65, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: -proxy.size.width * 0.15, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark ? [
                            Color.orbixLavender.opacity(0.18),
                            Color.orbixLavenderSoft.opacity(0.24),
                            Color.orbixLavender.opacity(0.10)
                        ] : [
                            Color.orbixLavender.opacity(0.35),
                            Color.orbixLavenderSoft.opacity(0.55),
                            Color.orbixLavender.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 60)
            }
        }
    }
}

// MARK: - Button Press Style
struct PillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
