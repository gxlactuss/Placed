import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    enum SessionState: Equatable { case checking, authenticated, unauthenticated }

    @Published var sessionState: SessionState = .unauthenticated
    @Published var currentUser: User?
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let network = NetworkManager.shared
    private let oauthService = OAuthService()

    init() {
        network.authTokenProvider = { KeychainService.loadToken() }
        network.onUnauthorized = { [weak self] in
            Task { @MainActor in self?.handleExpiredSession() }
        }
        if KeychainService.loadToken() != nil {
            sessionState = .checking
            Task { await validateSession() }
        }
    }

    private func validateSession() async {
        do {
            let user: User = try await network.request(path: "/api/auth/me")
            currentUser = user
            sessionState = .authenticated
        } catch NetworkError.unauthorized {
            KeychainService.deleteToken()
            currentUser = nil
            sessionState = .unauthenticated
        } catch {
            sessionState = .authenticated
        }
    }

    func login(email: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let response: TokenResponse = try await network.request(
                path: "/api/auth/login",
                method: .post,
                body: LoginRequest(email: email, password: password),
                requiresAuth: false
            )
            handleAuthSuccess(response)
        } catch {
            errorMessage = message(for: error)
        }
    }

    func signup(email: String, password: String, fullName: String?, targetRole: String?) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let response: TokenResponse = try await network.request(
                path: "/api/auth/signup",
                method: .post,
                body: SignupRequest(email: email, password: password, fullName: fullName, targetRole: targetRole),
                requiresAuth: false
            )
            handleAuthSuccess(response)
        } catch {
            errorMessage = message(for: error)
        }
    }

    @discardableResult
    func verifyEmail(code: String) async -> Bool {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let updated: User = try await network.request(
                path: "/api/auth/verify",
                method: .post,
                body: VerifyCodeRequest(code: code)
            )
            currentUser = updated
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func resendVerification() async {
        errorMessage = nil
        do {
            try await network.send(path: "/api/auth/resend-verification", method: .post)
        } catch {
            errorMessage = message(for: error)
        }
    }

    @discardableResult
    func completeOnboarding(fullName: String, targetRole: String) async -> Bool {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let body = UserUpdate(fullName: fullName, targetRole: targetRole, onboarded: true)
        do {
            let updated: User = try await network.request(path: "/api/auth/me", method: .patch, body: body)
            currentUser = updated
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func updateTargetRole(_ role: String) async {
        guard let updated: User = try? await network.request(
            path: "/api/auth/me",
            method: .patch,
            body: UserUpdate(targetRole: role)
        ) else { return }
        currentUser = updated
    }

    func signInWithOAuth(_ provider: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await oauthService.authenticate(
                url: network.oauthLoginURL(provider: provider),
                callbackScheme: "placementprep"
            )
            KeychainService.saveToken(token)
            await validateSession()
            if sessionState != .authenticated {
                errorMessage = "Signed in, but couldn't load your profile. Please try again."
            }
        } catch OAuthError.cancelled {
        } catch let OAuthError.provider(code) {
            errorMessage = Self.oauthMessage(for: code)
        } catch {
            errorMessage = "Sign-in didn't complete. Please try again."
        }
    }

    private static func oauthMessage(for code: String) -> String {
        switch code {
        case "provider_not_configured": return "This sign-in option isn't set up yet."
        case "no_email": return "That account has no shareable email. Try another way."
        case "invalid_state": return "Sign-in expired. Please try again."
        default: return "Sign-in didn't complete. Please try again."
        }
    }

    func logout() {
        KeychainService.deleteToken()
        currentUser = nil
        errorMessage = nil
        sessionState = .unauthenticated
    }

    private func handleExpiredSession() {
        guard sessionState != .unauthenticated else { return }
        KeychainService.deleteToken()
        currentUser = nil
        sessionState = .unauthenticated
    }

    private func handleAuthSuccess(_ response: TokenResponse) {
        KeychainService.saveToken(response.accessToken)
        currentUser = response.user
        errorMessage = nil
        sessionState = .authenticated
    }

    private func message(for error: Error) -> String {
        if case let NetworkError.server(_, body) = error,
           let data = body.data(using: .utf8),
           let detail = try? JSONDecoder().decode(ServerDetail.self, from: data) {
            return detail.detail
        }
        return error.localizedDescription
    }

    private struct ServerDetail: Decodable { let detail: String }
}
