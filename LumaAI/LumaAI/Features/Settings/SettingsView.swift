import SwiftUI

public struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @ObservedObject private var userPreferences: UserPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var showingLogoutAlert: Bool = false
    @State private var showingClearAlert: Bool = false

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
            List {
                // Section: Account
                accountSection

                // Section: Backend Infrastructure
                backendHealthSection

                // Section: Voice & Speech Experience
                voiceSettingsSection

                // Section: System & Feedback
                systemSection

                // Section: About
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.lumaCanvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(LumaTypography.headline)
                    .foregroundColor(.lumaPrimaryText)
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
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section(header: Text("ACCOUNT").font(LumaTypography.caption)) {
            if let user = viewModel.authManager.currentUser {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.lumaSurfaceElevated)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(user.email.prefix(1).uppercased())
                                .font(LumaTypography.headline)
                                .foregroundColor(.lumaPrimaryText)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.fullName)
                            .font(LumaTypography.body)
                            .foregroundColor(.lumaPrimaryText)

                        Text(user.email)
                            .font(LumaTypography.caption)
                            .foregroundColor(.lumaSecondaryText)
                    }
                }
                .padding(.vertical, 4)

                Button(role: .destructive, action: {
                    showingLogoutAlert = true
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .foregroundColor(.lumaError)
                }
            } else {
                Text("Not signed in")
                    .font(LumaTypography.caption)
                    .foregroundColor(.lumaSecondaryText)
            }
        }
        .listRowBackground(Color.lumaSurface)
    }

    private var backendHealthSection: some View {
        Section(header: Text("BACKEND INFRASTRUCTURE").font(LumaTypography.caption)) {
            HStack {
                Text("Render API Service")
                    .font(LumaTypography.body)
                    .foregroundColor(.lumaPrimaryText)
                Spacer()
                if viewModel.isCheckingHealth {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if viewModel.serverHealth?.status == "ok" {
                    StatusBadge("Operational", status: .online)
                } else {
                    StatusBadge("Offline", status: .offline)
                }
            }

            if let ai = viewModel.aiHealth {
                HStack {
                    Text("AI Inference Engine")
                        .font(LumaTypography.body)
                        .foregroundColor(.lumaPrimaryText)
                    Spacer()
                    Text(ai.model ?? "Luma AI Engine")
                        .font(LumaTypography.caption)
                        .foregroundColor(.lumaSecondaryText)
                }

                HStack {
                    Text("Model Status")
                        .font(LumaTypography.body)
                        .foregroundColor(.lumaPrimaryText)
                    Spacer()
                    StatusBadge(
                        ai.modelAvailable == true ? "Ready" : "Unavailable",
                        status: ai.modelAvailable == true ? .online : .error
                    )
                }
            }

            Button(action: {
                HapticFeedback.light()
                Task {
                    await viewModel.checkServerHealth()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Backend Status")
                }
                .font(LumaTypography.caption)
                .foregroundColor(.lumaAccent)
            }
        }
        .listRowBackground(Color.lumaSurface)
    }

    private var voiceSettingsSection: some View {
        Section(
            header: Text("VOICE & SPEECH").font(LumaTypography.caption),
            footer: Text("Fine-tune the tone and tempo of the assistant's natural soft female voice.")
                .font(LumaTypography.caption)
                .foregroundColor(.lumaTertiaryText)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speaking Rate")
                        .font(LumaTypography.body)
                        .foregroundColor(.lumaPrimaryText)
                    Spacer()
                    Text(String(format: "%.2fx", userPreferences.voiceSpeakingRate / 0.5))
                        .font(LumaTypography.caption)
                        .foregroundColor(.lumaSecondaryText)
                }

                Slider(value: $userPreferences.voiceSpeakingRate, in: 0.35...0.65, step: 0.01)
                    .tint(.lumaPrimaryText)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pitch Warmth")
                        .font(LumaTypography.body)
                        .foregroundColor(.lumaPrimaryText)
                    Spacer()
                    Text(String(format: "%.2fx", userPreferences.voicePitchMultiplier))
                        .font(LumaTypography.caption)
                        .foregroundColor(.lumaSecondaryText)
                }

                Slider(value: $userPreferences.voicePitchMultiplier, in: 0.9...1.3, step: 0.02)
                    .tint(.lumaPrimaryText)
            }
            .padding(.vertical, 4)

            Button("Reset to Natural Female Voice") {
                HapticFeedback.light()
                viewModel.resetVoiceSettings()
            }
            .font(LumaTypography.caption)
            .foregroundColor(.lumaAccent)
        }
        .listRowBackground(Color.lumaSurface)
    }

    private var systemSection: some View {
        Section(header: Text("EXPERIENCE").font(LumaTypography.caption)) {
            Toggle(isOn: $userPreferences.hapticsEnabled) {
                Text("Haptic Feedback")
                    .font(LumaTypography.body)
                    .foregroundColor(.lumaPrimaryText)
            }
            .tint(.lumaAccent)
        }
        .listRowBackground(Color.lumaSurface)
    }

    private var aboutSection: some View {
        Section(header: Text("ABOUT").font(LumaTypography.caption)) {
            HStack {
                Text("Version")
                    .font(LumaTypography.body)
                    .foregroundColor(.lumaPrimaryText)
                Spacer()
                Text("1.0.0 (Native Swift)")
                    .font(LumaTypography.caption)
                    .foregroundColor(.lumaSecondaryText)
            }

            HStack {
                Text("Architecture")
                    .font(LumaTypography.body)
                    .foregroundColor(.lumaPrimaryText)
                Spacer()
                Text("SwiftUI + AVFoundation")
                    .font(LumaTypography.caption)
                    .foregroundColor(.lumaSecondaryText)
            }

            HStack {
                Text("Storage")
                    .font(LumaTypography.body)
                    .foregroundColor(.lumaPrimaryText)
                Spacer()
                Text("Device Isolated JSON")
                    .font(LumaTypography.caption)
                    .foregroundColor(.lumaSecondaryText)
            }
        }
        .listRowBackground(Color.lumaSurface)
    }
}
