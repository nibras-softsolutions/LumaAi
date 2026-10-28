import Foundation
import Combine

public enum AuthMode {
    case signIn
    case register
}

@MainActor
public final class AuthViewModel: ObservableObject {
    @Published public var mode: AuthMode = .signIn
    @Published public var fullName: String = ""
    @Published public var email: String = ""
    @Published public var password: String = ""
    @Published public var isLoading: Bool = false
    @Published public var isGoogleLoading: Bool = false
    @Published public var errorMessage: String?

    private let authManager: AuthenticationManager

    public init(authManager: AuthenticationManager) {
        self.authManager = authManager
    }

    public var isFormValid: Bool {
        let isEmailValid = email.contains("@") && email.contains(".") && email.count >= 5
        let isPasswordValid = password.count >= 12

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

        do {
            if mode == .signIn {
                try await authManager.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
            } else {
                try await authManager.register(
                    fullName: fullName.trimmingCharacters(in: .whitespaces),
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    public func signInWithGoogle() async {
        isGoogleLoading = true
        errorMessage = nil

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
        mode = (mode == .signIn) ? .register : .signIn
    }
}
