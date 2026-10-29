import SwiftUI

public struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @ObservedObject private var userPreferences: UserPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var showingLogoutAlert: Bool = false

    public init(
        authManager: AuthenticationManager,
        userPreferences: UserPreferences = .shared,
        apiClient: APIClientProtocol
    ) {
        _viewModel = StateObject(
            wrappedValue: SettingsViewModel(
                authManager: authManager,
                userPreferences: userPreferences,
                apiClient: apiClient
            )
        )
        self.userPreferences = userPreferences
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    // Section 1: Account
                    accountSection

                    // Section 2: AI Infrastructure
                    aiInfrastructureSection

                    // Section 3: Voice & Speech
                    voiceAndSpeechSection

                    // Section 4: App Preferences
                    appPreferencesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .background(Color.settingsBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.settingsPrimaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.settingsPrimaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
            }
            .task {
                await viewModel.checkServerHealth()
            }
            .confirmationDialog("Sign Out of Luma AI?", isPresented: $showingLogoutAlert, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await viewModel.logout()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out? You will need to sign in again to access your account.")
            }
        }
    }

    // MARK: - Section 1: Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Account")

            settingsCard {
                if let user = viewModel.authManager.currentUser {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.lumaSurfaceElevated)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(user.fullName.prefix(1).uppercased().isEmpty ? user.email.prefix(1).uppercased() : user.fullName.prefix(1).uppercased())
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.settingsPrimaryText)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.fullName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.settingsPrimaryText)

                            Text(user.email)
                                .font(.system(size: 13))
                                .foregroundColor(.settingsSecondaryText)
                        }

                        Spacer()
                    }
                    .padding(16)

                    cardDivider

                    Button(action: {
                        showingLogoutAlert = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16, weight: .medium))
                            Text("Sign Out")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.lumaError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                } else {
                    HStack {
                        Text("Not signed in")
                            .font(.system(size: 14))
                            .foregroundColor(.settingsSecondaryText)
                        Spacer()
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Section 2: AI Infrastructure

    private var aiInfrastructureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("AI Infrastructure")

            settingsCard {
                // Row 1: Render API Service
                HStack {
                    Text("Render API Service")
                        .font(.system(size: 15))
                        .foregroundColor(.settingsPrimaryText)
                    Spacer()
                    statusBadgeView(for: viewModel.statusState)
                }
                .padding(16)

                cardDivider

                // Row 2: AI Inference Engine
                HStack {
                    Text("AI Inference Engine")
                        .font(.system(size: 15))
                        .foregroundColor(.settingsPrimaryText)
                    Spacer()
                    Text(viewModel.aiHealth?.model ?? "openai/gpt-oss-120b")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.settingsSecondaryText)
                }
                .padding(16)

                cardDivider

                // Row 3: Model Status
                HStack {
                    Text("Model Status")
                        .font(.system(size: 15))
                        .foregroundColor(.settingsPrimaryText)
                    Spacer()
                    if viewModel.isCheckingHealth {
                        Text("Checking…")
                            .font(.system(size: 13))
                            .foregroundColor(.settingsSecondaryText)
                    } else if viewModel.aiHealth?.modelAvailable == true {
                        modelStatusBadge("Ready", isReady: true)
                    } else {
                        modelStatusBadge("Unavailable", isReady: false)
                    }
                }
                .padding(16)

                cardDivider

                // Row 4: Latency & Last Checked Time
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "gauge.medium")
                            .font(.system(size: 12))
                            .foregroundColor(.settingsSecondaryText)
                        Text(viewModel.latencyMs.map { "\($0) ms" } ?? "Latency: --")
                            .font(.system(size: 12))
                            .foregroundColor(.settingsSecondaryText)
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundColor(.settingsSecondaryText)
                        Text(viewModel.formattedLastChecked)
                            .font(.system(size: 12))
                            .foregroundColor(.settingsSecondaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                cardDivider

                // Row 5: Refresh Action
                Button(action: {
                    HapticFeedback.light()
                    Task {
                        await viewModel.checkServerHealth()
                    }
                }) {
                    HStack(spacing: 6) {
                        if viewModel.isCheckingHealth {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(viewModel.isCheckingHealth ? "Checking Infrastructure…" : "Refresh Backend Status")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.lumaAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Section 3: Voice & Speech

    private var voiceAndSpeechSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Voice & Speech")

            settingsCard {
                // Voice Selection
                HStack {
                    Text("Voice Selection")
                        .font(.system(size: 15))
                        .foregroundColor(.settingsPrimaryText)
                    Spacer()
                    Text("Natural Female Voice (Ava)")
                        .font(.system(size: 13))
                        .foregroundColor(.settingsSecondaryText)
                }
                .padding(16)

                cardDivider

                // Speaking Rate
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Speaking Rate")
                            .font(.system(size: 15))
                            .foregroundColor(.settingsPrimaryText)
                        Spacer()
                        Text(String(format: "%.2fx", userPreferences.voiceSpeakingRate / 0.50))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.settingsSecondaryText)
                    }

                    Slider(value: $userPreferences.voiceSpeakingRate, in: 0.35...0.65, step: 0.01)
                        .tint(.settingsPrimaryText)
                }
                .padding(16)

                cardDivider

                // Pitch Warmth
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Pitch Warmth")
                            .font(.system(size: 15))
                            .foregroundColor(.settingsPrimaryText)
                        Spacer()
                        Text(String(format: "%.2fx", userPreferences.voicePitchMultiplier))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.settingsSecondaryText)
                    }

                    Slider(value: $userPreferences.voicePitchMultiplier, in: 0.90...1.30, step: 0.02)
                        .tint(.settingsPrimaryText)
                }
                .padding(16)

                cardDivider

                // Preview & Reset Controls
                HStack {
                    Button(action: {
                        HapticFeedback.light()
                        viewModel.playVoiceSample()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.isPlayingSample ? "stop.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13))
                            Text(viewModel.isPlayingSample ? "Stop Audio" : "Play Sample Audio")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.lumaAccent)
                    }

                    Spacer()

                    Button(action: {
                        HapticFeedback.light()
                        viewModel.resetVoiceSettings()
                    }) {
                        Text("Reset to Defaults")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.settingsSecondaryText)
                    }
                }
                .padding(16)
            }

            Text("Fine-tune the tone and tempo of the assistant's natural soft female voice.")
                .font(.system(size: 12))
                .foregroundColor(.settingsSectionLabel)
                .padding(.horizontal, 8)
                .padding(.top, 2)
        }
    }

    // MARK: - Section 4: App Preferences

    private var appPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("App Preferences")

            settingsCard {
                // Haptic Feedback
                Toggle(isOn: $userPreferences.hapticsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Haptic Feedback")
                            .font(.system(size: 15))
                            .foregroundColor(.settingsPrimaryText)
                        Text("Subtle tactile vibration on interactions")
                            .font(.system(size: 12))
                            .foregroundColor(.settingsSecondaryText)
                    }
                }
                .tint(.lumaAccent)
                .padding(16)

                cardDivider

                // Appearance
                HStack {
                    Text("Appearance")
                        .font(.system(size: 15))
                        .foregroundColor(.settingsPrimaryText)
                    Spacer()
                    Text("Dark Cinematic & Warm Canvas")
                        .font(.system(size: 13))
                        .foregroundColor(.settingsSecondaryText)
                }
                .padding(16)

                cardDivider

                // Data Privacy
                HStack {
                    Text("Data Privacy")
                        .font(.system(size: 15))
                        .foregroundColor(.settingsPrimaryText)
                    Spacer()
                    Text("Device-Isolated Storage")
                        .font(.system(size: 13))
                        .foregroundColor(.settingsSecondaryText)
                }
                .padding(16)

                cardDivider

                // Application Info
                HStack {
                    Text("Version")
                        .font(.system(size: 15))
                        .foregroundColor(.settingsPrimaryText)
                    Spacer()
                    Text("1.0.0 (Native Swift 5.9)")
                        .font(.system(size: 13))
                        .foregroundColor(.settingsSecondaryText)
                }
                .padding(16)
            }
        }
    }

    // MARK: - Reusable Visual Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(.settingsSectionLabel)
            .padding(.leading, 8)
            .padding(.bottom, 2)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(Color.settingsCard)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.settingsDivider, lineWidth: 1)
        )
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 1)
    }

    private func statusBadgeView(for state: ServiceStatusState) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor(state))
                .frame(width: 7, height: 7)

            Text(stateTitle(state))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(stateColor(state))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(stateColor(state).opacity(0.12))
        .clipShape(Capsule())
    }

    private func modelStatusBadge(_ title: String, isReady: Bool) -> some View {
        let color = isReady ? Color(red: 22/255, green: 163/255, blue: 74/255) : Color(red: 220/255, green: 38/255, blue: 38/255)
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func stateColor(_ state: ServiceStatusState) -> Color {
        switch state {
        case .loading:
            return .settingsSecondaryText
        case .operational:
            return Color(red: 22/255, green: 163/255, blue: 74/255) // #16A34A Green
        case .degraded:
            return Color(red: 217/255, green: 119/255, blue: 6/255) // #D97706 Amber
        case .unavailable:
            return Color(red: 220/255, green: 38/255, blue: 38/255) // #DC2626 Red
        }
    }

    private func stateTitle(_ state: ServiceStatusState) -> String {
        switch state {
        case .loading:
            return "Checking"
        case .operational:
            return "Operational"
        case .degraded:
            return "Degraded"
        case .unavailable:
            return "Unavailable"
        }
    }
}
