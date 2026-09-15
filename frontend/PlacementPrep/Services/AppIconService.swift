import UIKit

@MainActor
enum AppIconService {
    static var isAvailable: Bool { UIApplication.shared.supportsAlternateIcons }

    static var currentLevel: XPLevel {
        let name = UIApplication.shared.alternateIconName
        return XPLevel.allCases.first { $0.alternateIconName == name } ?? .fresher
    }

    @discardableResult
    static func apply(_ level: XPLevel) async -> Bool {
        guard isAvailable else { return false }
        let target = level.alternateIconName
        guard target != UIApplication.shared.alternateIconName else { return false }

        do {
            try await UIApplication.shared.setAlternateIconName(target)
            return true
        } catch {
            return false
        }
    }
}
