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

    /// Pale yellow at 0, the theme's amber at 0.5, its red at 1.
    static func ppHeat(_ temperature: Double) -> Color {
        let t = min(max(temperature, 0), 1)
        let pale = palette.colorScheme == .dark ? Color(hex: 0xE8DCA8) : Color(hex: 0xDCC374)
        return t < 0.5
            ? pale.ppBlend(with: palette.medium, by: t / 0.5)
            : palette.medium.ppBlend(with: palette.hard, by: (t - 0.5) / 0.5)
    }

    func ppBlend(with other: Color, by amount: Double) -> Color {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = CGFloat(min(max(amount, 0), 1))
        return Color(
            .sRGB,
            red: Double(r1 + (r2 - r1) * k),
            green: Double(g1 + (g2 - g1) * k),
            blue: Double(b1 + (b2 - b1) * k),
            opacity: Double(a1 + (a2 - a1) * k)
        )
    }

    static func ppScore(_ score: Double, middle: Color = .ppAccent) -> Color {
        switch score {
        case 8...: .ppEasy
        case 5..<8: middle
        default: .ppHard
        }
    }
}

extension View {
    func ppScreenBackground() -> some View {
        self
            .background(Color.ppGround.ignoresSafeArea())
            .preferredColorScheme(ThemeStore.shared.activeTheme.palette.colorScheme)
    }
}
