import Foundation
import UIKit

/// Focus mode for a practice session.
///
/// **It cannot switch on the system Do Not Disturb, and nothing here pretends
/// otherwise.** iOS exposes no public API for a third-party app to enable a
/// Focus — there is no entitlement for it, and the `App-Prefs:` URL trick is
/// private API that fails App Review. `FocusModeBriefing` is what closes that
/// gap: it points the student at the Shortcuts automation that *can* flip DND on
/// their behalf, which is the sanctioned route.
///
/// What this store does own is the part a sandboxed app is actually allowed to
/// do — hold the display awake for the length of a round — plus the persisted
/// on/off state the two entry points share.
@MainActor
@Observable
final class FocusModeStore {

    private static let enabledKey = "focusModeEnabled"
    private static let briefedKey = "focusModeBriefed"

    private(set) var isOn: Bool
    /// Whether the one-time explainer has been shown. Gates the first tap so the
    /// button can't quietly under-deliver on the DND part.
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

    /// The one system-level lever a sandboxed app really has: stop the display
    /// sleeping mid-answer, which matters most in the hands-free voice round.
    /// UIKit scopes this to the foreground, so leaving the toggle on overnight
    /// can't sit there burning battery.
    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isOn
    }
}

extension FocusModeStore {
    /// In-memory store for previews, so previews never touch real defaults.
    static func preview(on: Bool = false, briefed: Bool = true) -> FocusModeStore {
        let defaults = UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        defaults.set(on, forKey: "focusModeEnabled")
        defaults.set(briefed, forKey: "focusModeBriefed")
        return FocusModeStore(defaults: defaults)
    }
}
