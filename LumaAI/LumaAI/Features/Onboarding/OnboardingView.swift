import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var preferences: UserPreferences
    let onFinished: () -> Void

    @State private var currentStep = 0

    private struct StepInfo {
        let stepNumber: String
        let title: String
        let description: String
        let icon: String
    }

    private let steps: [StepInfo] = [
        StepInfo(
            stepNumber: "01 — Welcome to Luma AI",
            title: "A thoughtful space to think.",
            description: "Meet Luma AI, your personal space to explore ideas, solve problems, and discover new possibilities.",
            icon: "sparkles"
        ),
        StepInfo(
            stepNumber: "02 — Intelligent Workspace",
            title: "Conversational intelligence.",
            description: "Chat naturally, generate high-quality images, and speak seamlessly with two-way voice mode.",
            icon: "bubble.left.and.bubble.right"
        ),
        StepInfo(
            stepNumber: "03 — Privacy & Clarity",
            title: "Your data stays yours.",
            description: "Secure local keychain storage, zero third-party tracking, and transparent server connectivity.",
            icon: "lock.shield"
        )
    ]

    public var body: some View {
        ZStack {
            Color.lumaCanvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.lumaPrimaryText)
                        Text("Luma AI")
                            .font(LumaTypography.headline)
                            .foregroundColor(.lumaPrimaryText)
                    }

                    Spacer()

                    Button(action: {
                        HapticFeedback.light()
                        completeOnboarding()
                    }) {
                        Text("Skip")
                            .font(LumaTypography.subheadline)
                            .foregroundColor(.lumaSecondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // Content Slider
                TabView(selection: $currentStep) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        VStack(spacing: 24) {
                            Circle()
                                .fill(Color.lumaSurfaceElevated)
                                .frame(width: 96, height: 96)
                                .overlay(
                                    Image(systemName: steps[index].icon)
                                        .font(.system(size: 40, weight: .light))
                                        .foregroundColor(.lumaPrimaryText)
                                )
                                .padding(.bottom, 8)

                            VStack(spacing: 12) {
                                Text(steps[index].stepNumber)
                                    .font(LumaTypography.captionMedium)
                                    .foregroundColor(.lumaSecondaryText)
                                    .textCase(.uppercase)

                                Text(steps[index].title)
                                    .font(LumaTypography.largeTitle)
                                    .foregroundColor(.lumaPrimaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)

                                Text(steps[index].description)
                                    .font(LumaTypography.body)
                                    .foregroundColor(.lumaSecondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                    .lineSpacing(4)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 380)

                Spacer()

                // Footer Controls
                VStack(spacing: 20) {
                    // Page Indicator Dots
                    HStack(spacing: 8) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            Capsule()
                                .fill(currentStep == index ? Color.lumaPrimaryText : Color.lumaBorder)
                                .frame(width: currentStep == index ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentStep)
                        }
                    }

                    HStack(spacing: 12) {
                        if currentStep > 0 {
                            Button(action: {
                                HapticFeedback.light()
                                withAnimation {
                                    currentStep -= 1
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .font(LumaTypography.bodyMedium)
                                .foregroundColor(.lumaPrimaryText)
                                .frame(width: 100, height: 50)
                                .background(Color.lumaSurfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.lumaBorder, lineWidth: 1)
                                )
                            }
                        }

                        LumaButton(
                            currentStep == steps.count - 1 ? "Get Started" : "Continue",
                            style: .primary
                        ) {
                            if currentStep < steps.count - 1 {
                                withAnimation {
                                    currentStep += 1
                                }
                            } else {
                                completeOnboarding()
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func completeOnboarding() {
        preferences.hasCompletedOnboarding = true
        onFinished()
    }
}
