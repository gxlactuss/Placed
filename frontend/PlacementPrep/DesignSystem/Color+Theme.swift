import SwiftUI

extension Color {
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

extension Color {

    private static var palette: Palette { ThemeStore.shared.activeTheme.palette }

    static var ppGround: Color { palette.ground }
    static var ppSurface: Color { palette.surface }
    static var ppElevated: Color { palette.elevated }

    static var ppText: Color { palette.text }
    static var ppMuted: Color { palette.muted }

    static var ppAccent300: Color { palette.accent300 }
    static var ppAccent400: Color { palette.accent400 }
    static var ppAccent: Color { palette.accent }
    static var ppAccent700: Color { palette.accent700 }
    static var ppAccentSection: Color { palette.accentSection }
    static var ppOnAccent: Color { palette.onAccent }

    static var ppEasy: Color { palette.easy }
    static var ppMedium: Color { palette.medium }
    static var ppHard: Color { palette.hard }

    static var ppBorder: Color { palette.border }
    static var ppBorderStrong: Color { palette.borderStrong }
}

extension View {
    func ppScreenBackground() -> some View {
        self
            .background(Color.ppGround.ignoresSafeArea())
            .preferredColorScheme(ThemeStore.shared.activeTheme.palette.colorScheme)
    }
}
