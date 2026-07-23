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

// MARK: - Palette tokens
//
// Every screen reads colour only through these tokens — never a raw literal.
// Each one resolves through `ThemeStore.shared`, so swapping the active theme
// repaints the whole app without touching a call site. The values themselves
// live in `Theme.swift` (`Palette`), one struct per theme.
//
// Because the getters read the observable store inside each view's body, a
// theme change invalidates exactly the views that draw a themed colour.
//
// The original "Ledger" reading still holds for the default theme: an editorial
// ink ground, warm paper-white text, one amber accent, depth from hairlines not
// shadows. The other themes re-map the same slots.

extension Color {

    private static var palette: Palette { ThemeStore.shared.activeTheme.palette }

    // Core surfaces.
    static var ppGround: Color { palette.ground }
    static var ppSurface: Color { palette.surface }
    static var ppElevated: Color { palette.elevated }

    // Content.
    static var ppText: Color { palette.text }
    static var ppMuted: Color { palette.muted }

    // Accent. 300/400 are the tints that read as accent *text* on the theme's
    // ground; 700 is dim; `section` is the wash behind the hero card.
    static var ppAccent300: Color { palette.accent300 }
    static var ppAccent400: Color { palette.accent400 }
    static var ppAccent: Color { palette.accent }
    static var ppAccent700: Color { palette.accent700 }
    static var ppAccentSection: Color { palette.accentSection }
    /// The mark colour that sits on top of the accent (button labels, ticks).
    static var ppOnAccent: Color { palette.onAccent }

    // Difficulty semantics.
    static var ppEasy: Color { palette.easy }
    static var ppMedium: Color { palette.medium }
    static var ppHard: Color { palette.hard }

    /// Hairlines — the only depth cue in this system.
    static var ppBorder: Color { palette.border }
    static var ppBorderStrong: Color { palette.borderStrong }
}

// MARK: - Screen chrome

extension View {
    /// Applies the app ground colour edge to edge and matches the system colour
    /// scheme to the active theme (dark or light). Use on screen roots so
    /// previews match the shipped appearance.
    func ppScreenBackground() -> some View {
        self
            .background(Color.ppGround.ignoresSafeArea())
            .preferredColorScheme(ThemeStore.shared.activeTheme.palette.colorScheme)
    }
}
