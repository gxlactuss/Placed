import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let network = NetworkManager.shared

    init() {
        network.authTokenProvider = { KeychainService.loadToken() }
        isAuthenticated = KeychainService.loadToken() != nil
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

    func logout() {
        KeychainService.deleteToken()
        currentUser = nil
        isAuthenticated = false
    }

    private func handleAuthSuccess(_ response: TokenResponse) {
        KeychainService.saveToken(response.accessToken)
        currentUser = response.user
        isAuthenticated = true
    }
}
