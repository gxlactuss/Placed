import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?

    private let network = NetworkManager.shared

    init() {
        network.authTokenProvider = { KeychainService.loadToken() }
        isAuthenticated = KeychainService.loadToken() != nil
    }

    func login(email: String, password: String) async {
        do {
            let response: TokenResponse = try await network.request(
                path: "/api/auth/login",
                method: .post,
                body: LoginRequest(email: email, password: password),
                requiresAuth: false
            )
            handleAuthSuccess(response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signup(email: String, password: String, fullName: String?, targetRole: String?) async {
        do {
            let response: TokenResponse = try await network.request(
                path: "/api/auth/signup",
                method: .post,
                body: SignupRequest(email: email, password: password, fullName: fullName, targetRole: targetRole),
                requiresAuth: false
            )
            handleAuthSuccess(response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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
