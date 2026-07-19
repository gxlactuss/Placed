import SwiftUI

extension Color {
    /// Creates a color from a packed 24-bit RGB literal, e.g. `Color(hex: 0x0E0F12)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Ledger palette
//
// Editorial dark: a neutral ink ground with no blue cast, warm paper-white
// text, and a single amber accent used sparingly — headlines, selection, and
// the hero card. Depth comes from hairlines and typography, not shadows or
// gradients. Difficulty colours are desaturated so they read as annotations,
// not candy.

extension Color {

    // Core surfaces — neutral greys, warmed very slightly.
    static let ppGround = Color(hex: 0x0E0F12)
    static let ppSurface = Color(hex: 0x17181D)
    static let ppElevated = Color(hex: 0x202127)

    // Content
    static let ppText = Color(hex: 0xF2F1EC)
    static let ppMuted = Color(hex: 0x8E9099)

    // Accent · amber. The tint scale keeps the old token names so call sites
    // don't churn: 300/400 are lighter tints, 700 is dim, `section` is a wash.
    static let ppAccent300 = Color(hex: 0xF2CD8C)
    static let ppAccent400 = Color(hex: 0xECB55E)
    static let ppAccent = Color(hex: 0xE8A33D)
    static let ppAccent700 = Color(hex: 0x8F6320)
    static let ppAccentSection = Color(hex: 0x261E10)

    // Difficulty semantics — muted sage / ochre / clay.
    static let ppEasy = Color(hex: 0x84B394)
    static let ppMedium = Color(hex: 0xC9A15E)
    static let ppHard = Color(hex: 0xC97F74)

    /// Hairlines — the only depth cue in this system.
    static let ppBorder = Color.white.opacity(0.08)
    static let ppBorderStrong = Color.white.opacity(0.16)
}

// MARK: - Screen chrome

extension View {
    /// Applies the app ground colour edge to edge and locks the view to dark mode.
    /// Use on screen roots so previews match the shipped appearance.
    func ppScreenBackground() -> some View {
        self
            .background(Color.ppGround.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}
