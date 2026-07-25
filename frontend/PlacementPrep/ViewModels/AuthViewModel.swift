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
