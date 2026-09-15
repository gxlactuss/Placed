import SwiftUI

extension Category {
    struct Palette {
        let top: Color
        let bottom: Color
        let border: Color
        let glyph: Color
    }

    var palette: Palette {
        switch self {
        case .csFundamentals:
            Palette(top: Color(hex: 0x00375B), bottom: Color(hex: 0x00182A),
                    border: Color(hex: 0x085B87), glyph: Color(hex: 0x9AD9FF))
        case .dsa:
            Palette(top: Color(hex: 0x003F1D), bottom: Color(hex: 0x001C0B),
                    border: Color(hex: 0x17653C), glyph: Color(hex: 0xA1E3B7))
        case .aptitude:
            Palette(top: Color(hex: 0x3A2659), bottom: Color(hex: 0x1A1029),
                    border: Color(hex: 0x5E4784), glyph: Color(hex: 0xDAC4FF))
        case .role:
            Palette(top: Color(hex: 0x5A3210), bottom: Color(hex: 0x291606),
                    border: Color(hex: 0x8A5A21), glyph: Color(hex: 0xFFD9A8))
        }
    }

    var badgeSymbol: String {
        switch self {
        case .csFundamentals: "cpu"
        case .dsa: "point.3.connected.trianglepath.dotted"
        case .aptitude: "brain"
        case .role: "person.crop.rectangle.badge.plus"
        }
    }
}

struct PPCategoryBadge: View {

    let category: Category
    var symbol: String?
    var size: CGFloat = 56

    var body: some View {
        let palette = category.palette

        Image(systemName: symbol ?? category.badgeSymbol)
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
