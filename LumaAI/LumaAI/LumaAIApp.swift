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
            } else if !appEnv.authManager.isAuthenticated {
                AuthView(
                    viewModel: AuthViewModel(authManager: appEnv.authManager),
                    startInEmailLogin: CommandLine.arguments.contains("-showLogin")
                )
            } else {
                MainContainerView()
            }
        }
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
            } else {
                await appEnv.authManager.restoreSession()
            }
        }
    }
}
