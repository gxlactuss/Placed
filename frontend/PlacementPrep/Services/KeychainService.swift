import Foundation
import Security

/// Persists the JWT access token.
///
/// The Keychain is the intended home and the only one used on iOS. On macOS it
/// is conditional, because **an ad-hoc-signed build cannot write to it at all**:
/// a keychain item needs an access group, an access group comes from the signing
/// identity's Team ID, and ad-hoc signing has none (`TeamIdentifier=not set`).
/// `SecItemAdd` then fails with `errSecMissingEntitlement` (-34018).
///
/// That is not a hypothetical. The Mac app ships unsigned on purpose — the
/// audience is two developers, so it skips the $99 Developer ID (see
/// DISTRIBUTE-MAC.md) — and the symptom is vicious precisely because it is
/// silent: sign-in succeeds and the UI advances, then every authenticated
/// request afterwards goes out with no `Authorization` header, because
/// `NetworkManager.authTokenProvider` reads this store on each call and there is
/// no in-memory copy. The user sees a 401 on the very next screen. It was
/// reproduced on both the sandboxed Debug build and the unsigned Release build.
///
/// So: try the Keychain, and if it refuses, fall back to a 0600 file. The
/// fallback is engaged **only by an actual failure**, so iOS and any properly
/// signed Mac build never touch it and their behaviour is unchanged.
///
/// The fallback is a real, if modest, downgrade: a token in a file under the
/// user's home is readable by anything running as that user, where a keychain
/// item is not. On a Mac that cannot use the Keychain at all the alternative
/// isn't "something safer", it's "cannot stay signed in" — but if this ever
/// ships to people who aren't the two of us, sign it properly and this path
/// stops being reachable.
enum KeychainService {
    private static let tokenKey = "com.placementprep.accessToken"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
        ]
    }

    static func saveToken(_ token: String) {
        let data = Data(token.utf8)
        SecItemDelete(baseQuery as CFDictionary)

        var newItem = baseQuery
        newItem[kSecValueData as String] = data
        let status = SecItemAdd(newItem as CFDictionary, nil)

        if status == errSecSuccess {
            // Clear any fallback left by a previous unsigned build, so a signed
            // build doesn't keep reading a stale token from disk.
            removeFallbackFile()
        } else {
            NSLog("[auth] Keychain unavailable (OSStatus \(status)); using file fallback.")
            writeFallbackFile(data)
        }
    }

    static func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        return readFallbackFile()
    }

    static func deleteToken() {
        SecItemDelete(baseQuery as CFDictionary)
        removeFallbackFile()
    }

    // MARK: - File fallback

    /// `nil` if Application Support can't be resolved, in which case the app
    /// simply behaves as it did before: signed in for this launch only.
    private static var fallbackURL: URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let folder = support.appendingPathComponent("PlacementPrep", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("session.token", isDirectory: false)
    }

    /// Written via `createFile(atPath:contents:attributes:)` so the 0600 mode is
    /// applied as the file is created — `Data.write` then `chmod` would leave a
    /// brief window where the token sits there world-readable.
    private static func writeFallbackFile(_ data: Data) {
        guard let url = fallbackURL else { return }
        try? FileManager.default.removeItem(at: url)
        FileManager.default.createFile(
            atPath: url.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
    }

    private static func readFallbackFile() -> String? {
        guard let url = fallbackURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func removeFallbackFile() {
        guard let url = fallbackURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
