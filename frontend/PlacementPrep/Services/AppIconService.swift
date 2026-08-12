import UIKit

/// Swaps the home-screen icon for the one a tier unlocked.
///
/// Thin on purpose: iOS already remembers which alternate icon is active, so
/// there is nothing to persist here — `UIApplication.alternateIconName` is the
/// source of truth and `XPStore` decides what the student is *allowed* to pick.
///
/// **Until the icon art is in the asset catalog** there are no alternates
/// declared, `supportsAlternateIcons` is false, and every call here no-ops. The
/// tiers still unlock and the picker still shows them; applying one simply does
/// nothing yet, rather than failing loudly at the student.
@MainActor
enum AppIconService {

    /// False until alternate icons are declared in the bundle.
    static var isAvailable: Bool { UIApplication.shared.supportsAlternateIcons }

    /// The tier whose icon is currently on the home screen. `nil` alternate name
    /// means the shipped icon, which is `.fresher`'s.
    static var currentLevel: XPLevel {
        let name = UIApplication.shared.alternateIconName
        return XPLevel.allCases.first { $0.alternateIconName == name } ?? .fresher
    }

    /// Applies `level`'s icon. Returns whether the icon actually changed.
    ///
    /// iOS shows its own "you have changed the icon" alert on success, which is
    /// why this is only called at a real moment — a level-up, or a deliberate
    /// pick in the icon picker — and never speculatively on launch.
    @discardableResult
    static func apply(_ level: XPLevel) async -> Bool {
        guard isAvailable else { return false }
        let target = level.alternateIconName
        guard target != UIApplication.shared.alternateIconName else { return false }

        do {
            try await UIApplication.shared.setAlternateIconName(target)
            return true
        } catch {
            // The art for this tier isn't in the bundle yet, or the user denied
            // the change. Neither is worth interrupting them over.
            return false
        }
    }
}
