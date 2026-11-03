import UIKit

@MainActor
enum PPHaptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func miss() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func levelUp() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
