import SwiftUI

/// Rounded square holding an SF Symbol. Leads the practice mode cards, the
/// resume card, the streak card and the recommendation rows.
struct PPIconTile: View {

    let systemName: String
    var size: CGFloat = PPSize.iconTile
    var tint: Color = .ppAccent400
    var fill: Color = .ppElevated

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fill, in: .rect(cornerRadius: PPRadius.md))
            .accessibilityHidden(true)
    }
}

/// Circular avatar with a graceful fallback when no image has loaded yet.
struct PPAvatar: View {

    var image: Image?
    var initials: String = ""
    var diameter: CGFloat = 40

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(Color.ppAccent300)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.ppAccentSection)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(.circle)
        .overlay { Circle().strokeBorder(Color.ppBorderStrong, lineWidth: 1) }
    }
}

/// Compact pill pairing an icon with a value, e.g. the streak counter in the header.
struct PPIconPill: View {

    let systemName: String
    let text: String
    var tint: Color = .ppAccent400

    var body: some View {
        HStack(spacing: PPSpacing.xs) {
            Image(systemName: systemName)
            Text(text)
        }
        .font(.ppMicro)
        .foregroundStyle(tint)
        .padding(.horizontal, PPSpacing.md)
        .frame(height: 30)
        .background(Color.ppAccentSection, in: .capsule)
    }
}

#Preview("Icons") {
    VStack(alignment: .leading, spacing: PPSpacing.xl) {
        HStack(spacing: PPSpacing.md) {
            PPIconTile(systemName: "checklist")
            PPIconTile(systemName: "mic.fill")
            PPIconTile(systemName: "building.2.fill")
            PPIconTile(systemName: "play.fill")
            PPIconTile(systemName: "flame.fill")
            PPIconTile(systemName: "book.closed.fill")
        }

        HStack(spacing: PPSpacing.md) {
            PPAvatar(initials: "KS")
            PPIconPill(systemName: "flame.fill", text: "12")
        }
    }
    .padding(PPSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .ppScreenBackground()
}
