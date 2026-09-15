import AuthenticationServices
import UIKit

enum OAuthError: Error {
    case cannotStart
    case cancelled
    case provider(String)
}

@MainActor
final class OAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {

    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> String {
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? OAuthError.cannotStart)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: OAuthError.cannotStart)
            }
        }

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        if let token = items?.first(where: { $0.name == "token" })?.value, !token.isEmpty {
            return token
        }
        throw OAuthError.provider(items?.first(where: { $0.name == "error" })?.value ?? "unknown")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
