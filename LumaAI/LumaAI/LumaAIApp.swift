import SwiftUI
import GoogleSignIn

@main
struct LumaAIApp: App {
    @StateObject private var appEnv = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environmentObject(appEnv)
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    appEnv.handleDeepLink(url: url)
                }
        }
    }
}

struct RootContentView: View {
    @EnvironmentObject var appEnv: AppEnvironment
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var isOnboardingDismissed: Bool = false

    private var shouldShowOnboarding: Bool {
        if isOnboardingDismissed {
            return false
        }
        if CommandLine.arguments.contains("-skipOnboarding") || CommandLine.arguments.contains("-mockAuth") {
            return false
        }
        if CommandLine.arguments.contains("-showOnboarding") {
            return !preferences.hasCompletedOnboarding
        }
        return !preferences.hasCompletedOnboarding
    }

    var body: some View {
        Group {
            if appEnv.authManager.isRestoringSession {
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: "sparkle")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(.white)
                            )

                        Text("Luma AI")
                            .font(LumaTypography.title)
                            .foregroundColor(.white)

                        ProgressView()
                            .tint(.white.opacity(0.6))
                            .scaleEffect(0.9)
                            .padding(.top, 8)
                    }
                }
                .preferredColorScheme(.dark)
            } else if shouldShowOnboarding {
                OnboardingView(preferences: appEnv.userPreferences) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isOnboardingDismissed = true
                        preferences.hasCompletedOnboarding = true
                        appEnv.userPreferences.hasCompletedOnboarding = true
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity.combined(with: .scale(scale: 0.96))
                ))
            } else if !appEnv.authManager.isAuthenticated {
                AuthView(
                    viewModel: AuthViewModel(authManager: appEnv.authManager),
                    startInEmailLogin: CommandLine.arguments.contains("-showLogin")
                )
                .transition(.opacity)
            } else {
                MainContainerView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: shouldShowOnboarding)
        .animation(.easeInOut(duration: 0.35), value: appEnv.authManager.isAuthenticated)
        .task {
            if CommandLine.arguments.contains("-resetAuth") {
                await appEnv.authManager.logout()
            } else if CommandLine.arguments.contains("-mockAuth") {
                appEnv.authManager.setMockAuthenticatedUser()
                if CommandLine.arguments.contains("-showSettings") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        appEnv.showingSettings = true
                    }
                }
                if CommandLine.arguments.contains("-showVoice") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        appEnv.openVoiceMode()
                    }
                }
            } else {
                await appEnv.authManager.restoreSession()
            }

            for arg in CommandLine.arguments {
                if arg.hasPrefix("luma://"), let url = URL(string: arg) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        appEnv.handleDeepLink(url: url)
                    }
                }
            }
        }
    }
}
