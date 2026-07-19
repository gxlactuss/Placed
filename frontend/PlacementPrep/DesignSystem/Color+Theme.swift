import SwiftUI

extension Color {
    /// Creates a color from a packed 24-bit RGB literal, e.g. `Color(hex: 0x161826)`.
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

// MARK: - Nocturne palette

extension Color {

    // Core surfaces
    static let ppGround = Color(hex: 0x161826)
    static let ppSurface = Color(hex: 0x232532)
    static let ppElevated = Color(hex: 0x2B2E3D)

    // Content
    static let ppText = Color(hex: 0xE9E9ED)
    static let ppMuted = Color(hex: 0x9397AB)

    // Accent · blurple
    static let ppAccent300 = Color(hex: 0xD2CEFD)
    static let ppAccent400 = Color(hex: 0xB5ABFC)
    static let ppAccent = Color(hex: 0x9184D9)
    static let ppAccent700 = Color(hex: 0x5D5294)
    static let ppAccentSection = Color(hex: 0x262A60)

    // Difficulty semantics
    static let ppEasy = Color(hex: 0x5FBF95)
    static let ppMedium = Color(hex: 0xD9A95F)
    static let ppHard = Color(hex: 0xDD7A8A)

    /// Hairline used for card and control borders. The palette has no dedicated
    /// stroke token, so borders are a low-alpha lift off the elevated surface.
    static let ppBorder = Color.white.opacity(0.07)
    static let ppBorderStrong = Color.white.opacity(0.12)
}

// MARK: - Gradients

extension LinearGradient {
    /// Fill for the hero statistics card on the home screen.
    static let ppAccentCard = LinearGradient(
        colors: [Color(hex: 0x4A4385), Color.ppAccentSection],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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
