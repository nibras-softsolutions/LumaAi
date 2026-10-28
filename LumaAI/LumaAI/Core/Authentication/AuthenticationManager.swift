import Foundation
import Combine
import UIKit
import GoogleSignIn

@MainActor
public final class AuthenticationManager: ObservableObject {
    public static let googleIOSClientID = "172474086048-ke3r4ekgdm0vcak48j1bvqqb6msrmubh.apps.googleusercontent.com"
    public static let googleWebClientID = "172474086048-02bpfth3nc9md882lhc22bkfl2raojpd.apps.googleusercontent.com"

    @Published public private(set) var currentUser: User?
    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var isRestoringSession: Bool = true
    @Published public var authErrorMessage: String?

    private let apiClient: APIClientProtocol
    private let keychain: KeychainHelper
    private let userCacheKey = "cached_user_profile"

    public init(
        apiClient: APIClientProtocol,
        keychain: KeychainHelper = .shared
    ) {
        self.apiClient = apiClient
        self.keychain = keychain
    }

    public func restoreSession() async {
        isRestoringSession = true
        defer { isRestoringSession = false }

        do {
            let user: User = try await apiClient.request(.me, body: nil)
            self.currentUser = user
            self.isAuthenticated = true
            cacheUser(user)
        } catch {
            if case .offline = (error as? NetworkError), let cached = getCachedUser() {
                self.currentUser = cached
                self.isAuthenticated = true
            } else {
                self.currentUser = nil
                self.isAuthenticated = false
            }
        }
    }

    public func autoRegisterGuest() async {
        let guestId = UUID().uuidString.prefix(8).lowercased()
        let guestEmail = "guest_\(guestId)@luma.local"
        let guestPassword = "Guest_\(UUID().uuidString)!"
        let guestName = "Luma User"

        do {
            let req = RegisterRequest(fullName: guestName, email: guestEmail, password: guestPassword)
            let user: User = try await apiClient.request(.register, body: req)
            self.currentUser = user
            self.isAuthenticated = true
            cacheUser(user)
        } catch {
            self.currentUser = nil
            self.isAuthenticated = false
        }
    }

    public func signInWithGoogle(presentingViewController: UIViewController? = nil) async throws {
        authErrorMessage = nil

        let presenter: UIViewController
        if let vc = presentingViewController {
            presenter = vc
        } else if let topVC = Self.topViewController() {
            presenter = topVC
        } else {
            let error = NetworkError.serverError(statusCode: 0, message: "No root view controller available for Google Sign-In.")
            authErrorMessage = error.errorDescription
            throw error
        }

        let config = GIDConfiguration(
            clientID: Self.googleIOSClientID,
            serverClientID: Self.googleWebClientID
        )
        GIDSignIn.sharedInstance.configuration = config

        let signInResult: GIDSignInResult
        do {
            signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as NSError {
            if error.domain == kGIDSignInErrorDomain && error.code == -5 {
                // User cancelled Google Sign-In
                return
            }
            if let gidError = error as? GIDSignInError, gidError.code == .canceled {
                return
            }
            authErrorMessage = error.localizedDescription
            throw error
        }

        guard let idToken = signInResult.user.idToken?.tokenString, !idToken.isEmpty else {
            let err = NetworkError.serverError(statusCode: 0, message: "Google Sign-In completed without an ID token.")
            authErrorMessage = err.errorDescription
            throw err
        }

        let req = GoogleAuthRequest(idToken: idToken)
        do {
            let user: User = try await apiClient.request(.googleAuth, body: req)
            self.currentUser = user
            self.isAuthenticated = true
            cacheUser(user)
        } catch let err as NetworkError {
            authErrorMessage = err.errorDescription
            throw err
        } catch {
            authErrorMessage = error.localizedDescription
            throw error
        }
    }

    public func login(email: String, password: String) async throws {
        authErrorMessage = nil
        let req = LoginRequest(email: email, password: password)
        do {
            let user: User = try await apiClient.request(.login, body: req)
            self.currentUser = user
            self.isAuthenticated = true
            cacheUser(user)
        } catch let err as NetworkError {
            authErrorMessage = err.errorDescription
            throw err
        } catch {
            authErrorMessage = error.localizedDescription
            throw error
        }
    }

    public func register(fullName: String, email: String, password: String) async throws {
        authErrorMessage = nil
        let req = RegisterRequest(fullName: fullName, email: email, password: password)
        do {
            let user: User = try await apiClient.request(.register, body: req)
            self.currentUser = user
            self.isAuthenticated = true
            cacheUser(user)
        } catch let err as NetworkError {
            authErrorMessage = err.errorDescription
            throw err
        } catch {
            authErrorMessage = error.localizedDescription
            throw error
        }
    }

    public func logout() async {
        authErrorMessage = nil
        _ = try? await apiClient.request(.logout, body: nil) as ServerHealth
        GIDSignIn.sharedInstance.signOut()
        clearStoredSession()
        self.currentUser = nil
        self.isAuthenticated = false
        self.isRestoringSession = false
    }

    private func cacheUser(_ user: User) {
        if let data = try? JSONEncoder().encode(user) {
            keychain.save(data, for: userCacheKey)
        }
    }

    private func getCachedUser() -> User? {
        guard let data = keychain.read(for: userCacheKey) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    private func clearStoredSession() {
        keychain.delete(for: userCacheKey)
        UserDefaults.standard.removeObject(forKey: "luma_session_token")
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                if cookie.name == "luma_session" {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
        }
    }

    private static func topViewController(controller: UIViewController? = nil) -> UIViewController? {
        let base = controller ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(controller: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(controller: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(controller: presented)
        }
        return base
    }
}
