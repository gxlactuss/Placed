import SwiftUI

/// Per-category identity colours for the quiz tracks.
///
/// A deliberate exception to the Ledger "one amber accent, flat" rule: giving
/// each track its own tinted gradient badge lets a student recognise CS, DSA
/// and Aptitude at a glance in the list. The hues match the design mockup
/// (signal blue / circuit green / insight violet), converted from oklch to sRGB.
extension Category {

    /// The four tones a badge is built from, darkest fill to lightest glyph.
    struct Palette {
        let top: Color
        let bottom: Color
        let border: Color
        let glyph: Color
    }

    var palette: Palette {
        switch self {
        case .csFundamentals:   // signal blue
            Palette(top: Color(hex: 0x00375B), bottom: Color(hex: 0x00182A),
                    border: Color(hex: 0x085B87), glyph: Color(hex: 0x9AD9FF))
        case .dsa:              // circuit green
            Palette(top: Color(hex: 0x003F1D), bottom: Color(hex: 0x001C0B),
                    border: Color(hex: 0x17653C), glyph: Color(hex: 0xA1E3B7))
        case .aptitude:         // insight violet
            Palette(top: Color(hex: 0x3A2659), bottom: Color(hex: 0x1A1029),
                    border: Color(hex: 0x5E4784), glyph: Color(hex: 0xDAC4FF))
        case .role:             // ember — the track that is uniquely theirs
            Palette(top: Color(hex: 0x5A3210), bottom: Color(hex: 0x291606),
                    border: Color(hex: 0x8A5A21), glyph: Color(hex: 0xFFD9A8))
        }
    }

    /// SF Symbol chosen to echo the mockup's marks: a chip, a node graph and a
    /// mind.
    var badgeSymbol: String {
        switch self {
        case .csFundamentals: "cpu"
        case .dsa: "point.3.connected.trianglepath.dotted"
        case .aptitude: "brain"
        case .role: "person.crop.rectangle.badge.plus"
        }
    }
}

/// Tinted gradient badge holding a category's mark. Replaces the flat ruled
/// `PPIconTile` for the quiz category list.
struct PPCategoryBadge: View {

    let category: Category
    var size: CGFloat = 56

    var body: some View {
        let palette = category.palette

        Image(systemName: category.badgeSymbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(palette.glyph)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [palette.top, palette.bottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: size * 0.26)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Category badges") {
    VStack(spacing: PPSpacing.lg) {
        ForEach(Category.allCases) { category in
            HStack(spacing: PPSpacing.md) {
                PPCategoryBadge(category: category)
                Text(category.title).font(.ppHeadline)
                Spacer()
            }
        }
    }
    .foregroundStyle(Color.ppText)
    .padding(PPSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
