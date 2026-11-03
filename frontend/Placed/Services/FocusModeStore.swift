import Foundation
import UIKit

@MainActor
@Observable
final class FocusModeStore {

    private static let enabledKey = "focusModeEnabled"
    private static let briefedKey = "focusModeBriefed"

    private(set) var isOn: Bool
    private(set) var hasSeenBriefing: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isOn = defaults.bool(forKey: Self.enabledKey)
        self.hasSeenBriefing = defaults.bool(forKey: Self.briefedKey)
        applyIdleTimer()
    }

    func toggle() { setOn(!isOn) }

    func setOn(_ on: Bool) {
        guard isOn != on else { return }
        isOn = on
        defaults.set(on, forKey: Self.enabledKey)
        applyIdleTimer()
    }

    func markBriefed() {
        guard !hasSeenBriefing else { return }
        hasSeenBriefing = true
        defaults.set(true, forKey: Self.briefedKey)
    }

    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isOn
    }
}

extension FocusModeStore {
    static func preview(on: Bool = false, briefed: Bool = true) -> FocusModeStore {
        let defaults = UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        defaults.set(on, forKey: "focusModeEnabled")
        defaults.set(briefed, forKey: "focusModeBriefed")
        return FocusModeStore(defaults: defaults)
    }
}
