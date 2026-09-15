import Foundation
import Security

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
