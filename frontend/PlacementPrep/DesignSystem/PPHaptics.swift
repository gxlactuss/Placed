import UIKit

/// The app's haptic vocabulary, kept to four meanings so a buzz always says
/// something. Scattering generators through the views is how an app ends up
/// vibrating on every tap and teaching the user to ignore it.
///
/// Deliberately not fired for ordinary navigation — only for a result the
/// student would want confirmed without looking: an answer landing, a problem
/// ticked off, a tier crossed.
@MainActor
enum PPHaptics {

    /// Right answer, problem solved, round cleared.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Wrong answer. `.warning` rather than `.error` — a missed question is
    /// information, not a fault, and `.error`'s triple knock reads as a telling-off.
    static func miss() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Crossing an XP tier: the one moment that earns the heavier thud.
    static func levelUp() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// A small confirmation for a state change the user chose — un-ticking a
    /// problem, applying an icon.
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
