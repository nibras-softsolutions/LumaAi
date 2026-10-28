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
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

struct RootContentView: View {
    @EnvironmentObject var appEnv: AppEnvironment

    var body: some View {
        Group {
            if !appEnv.userPreferences.hasCompletedOnboarding {
                OnboardingView(preferences: appEnv.userPreferences) {
                    appEnv.userPreferences.hasCompletedOnboarding = true
                }
            } else if appEnv.authManager.isRestoringSession {
                ZStack {
                    Color.lumaCanvas
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        Circle()
                            .fill(Color.lumaSurfaceElevated)
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: "sparkle")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(.lumaPrimaryText)
                            )

                        Text("Luma AI")
                            .font(LumaTypography.title)
                            .foregroundColor(.lumaPrimaryText)

                        ProgressView()
                            .tint(.lumaSecondaryText)
                            .scaleEffect(0.9)
                            .padding(.top, 8)
                    }
                }
            } else if !appEnv.authManager.isAuthenticated {
                AuthView(viewModel: AuthViewModel(authManager: appEnv.authManager))
            } else {
                MainContainerView()
            }
        }
        .task {
            await appEnv.authManager.restoreSession()
        }
    }
}
