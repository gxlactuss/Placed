import Foundation

@MainActor
final class AuthViewModel: ObservableObject {

    /// The three states the app gate switches on. `.checking` is the brief window
    /// on launch while a stored token is validated against `/api/auth/me`.
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
        // A stored token is only *trusted* after `/me` confirms it — otherwise a
        // stale/expired token would drop the user into a dashboard that 401s on
        // every call. Validate before showing the tabs.
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
            // Token is genuinely invalid/expired — clear it and show login.
            KeychainService.deleteToken()
            currentUser = nil
            sessionState = .unauthenticated
        } catch {
            // Couldn't reach the backend (offline / server down). Don't punish
            // the user or discard a possibly-valid token — trust it for now; a
            // real 401 on a later authed call will bounce to login via
            // `handleExpiredSession`. (Quiz + company content works offline.)
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

    /// Confirms the emailed code. On success `currentUser` updates (isVerified
    /// true) and the gate advances past the verify screen.
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

    /// Requests a fresh verification code for the signed-in user.
    func resendVerification() async {
        errorMessage = nil
        do {
            try await network.send(path: "/api/auth/resend-verification", method: .post)
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// Saves the onboarding answers and flips `onboarded`. Returns whether it
    /// succeeded; on success `currentUser` updates and the gate moves to the tabs.
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

    /// Social sign-in (Google/GitHub). Opens the backend-brokered flow, stores
    /// the returned JWT, then validates it to load the user (which advances the
    /// gate — new accounts land on onboarding, verified by the provider).
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
            // User dismissed the sheet — not an error.
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

    /// An authenticated request came back 401 mid-session — the token lapsed, so
    /// drop straight back to login.
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

    /// Surfaces the backend's `detail` string (e.g. "Email already registered")
    /// rather than the generic "Server error (400): ..." wrapper.
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
