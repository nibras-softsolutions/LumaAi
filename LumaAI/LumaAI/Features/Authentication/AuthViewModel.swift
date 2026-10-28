import Foundation
import Combine

public enum AuthMode {
    case signIn
    case register
}

@MainActor
public final class AuthViewModel: ObservableObject {
    private static let rememberedEmailKey = "luma_remembered_email"

    @Published public var mode: AuthMode = .signIn
    @Published public var fullName: String = ""
    @Published public var email: String = ""
    @Published public var password: String = ""
    @Published public var rememberMe: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var isGoogleLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var statusMessage: String?

    private let authManager: AuthenticationManager

    public init(authManager: AuthenticationManager) {
        self.authManager = authManager
        if let savedEmail = UserDefaults.standard.string(forKey: Self.rememberedEmailKey), !savedEmail.isEmpty {
            self.email = savedEmail
            self.rememberMe = true
        }
    }

    public var isFormValid: Bool {
        let isEmailValid = email.contains("@") && email.contains(".") && email.count >= 5
        let isPasswordValid = password.count >= 6

        if mode == .register {
            return !fullName.trimmingCharacters(in: .whitespaces).isEmpty && isEmailValid && isPasswordValid
        } else {
            return isEmailValid && !password.isEmpty
        }
    }

    public func submit() async {
        guard isFormValid else { return }
        isLoading = true
        errorMessage = nil
        statusMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if mode == .signIn {
                try await authManager.login(email: trimmedEmail, password: password)
                if rememberMe {
                    UserDefaults.standard.set(trimmedEmail, forKey: Self.rememberedEmailKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: Self.rememberedEmailKey)
                }
            } else {
                try await authManager.register(
                    fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: trimmedEmail,
                    password: password
                )
                if rememberMe {
                    UserDefaults.standard.set(trimmedEmail, forKey: Self.rememberedEmailKey)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    public func requestPasswordReset(emailToReset: String) async -> Bool {
        let targetEmail = emailToReset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard targetEmail.contains("@") && targetEmail.contains(".") else {
            errorMessage = "Please enter a valid email address to reset password."
            return false
        }

        isLoading = true
        errorMessage = nil
        statusMessage = nil

        do {
            let msg = try await authManager.requestPasswordReset(email: targetEmail)
            statusMessage = msg
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    public func signInWithGoogle() async {
        isGoogleLoading = true
        errorMessage = nil
        statusMessage = nil

        do {
            try await authManager.signInWithGoogle()
        } catch {
            if let msg = authManager.authErrorMessage, !msg.isEmpty {
                errorMessage = msg
            }
        }

        isGoogleLoading = false
    }

    public func toggleMode() {
        errorMessage = nil
        statusMessage = nil
        mode = (mode == .signIn) ? .register : .signIn
    }
}
