import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Company mark for the LeetCode lists.
///
/// Logos sit on a light chip rather than directly on the ground. Brand marks
/// come in every colour — several are solid black (Apple, Uber, Bloomberg) and
/// would vanish against the near-black background. A consistent light tile is
/// legible for every logo without per-brand special-casing, and reads as a
/// deliberate "logo tile" rather than an accident.
///
/// Companies with no bundled logo fall back to an initials mark, which is what
/// the ~440 unbundled companies use.
struct PPCompanyLogo: View {

    let companyName: String
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PPRadius.sm)
                .fill(Color.ppText)

            if let image = CompanyLogoCache.shared.image(for: companyName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
            } else {
                Text(Self.initials(from: companyName))
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(Color.ppGround)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func initials(from name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return words.prefix(2).compactMap { $0.first.map(String.init) }
                .joined().uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

/// Caches decoded logos so scrolling a long company list does not hit the disk
/// on every row. Misses are remembered too, so a company without a logo does
/// not trigger a bundle lookup on each redraw.
@MainActor
final class CompanyLogoCache {

    static let shared = CompanyLogoCache()

    #if canImport(UIKit)
    private let cache = NSCache<NSString, UIImage>()
    #endif
    private var knownMissing: Set<String> = []

    private init() {}

    #if canImport(UIKit)
    func image(for companyName: String) -> UIImage? {
        if knownMissing.contains(companyName) { return nil }

        let key = companyName as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard
            let url = Bundle.main.url(
                forResource: companyName, withExtension: "png", subdirectory: "Logos"
            ) ?? Bundle.main.url(forResource: companyName, withExtension: "png"),
            let image = UIImage(contentsOfFile: url.path)
        else {
            knownMissing.insert(companyName)
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }
    #else
    func image(for companyName: String) -> UIImage? { nil }
    #endif
}

#Preview("Company logos") {
    let names = ["Google", "Apple", "Meta", "Netflix", "Uber", "Visa",
                 "Amazon", "LinkedIn", "Oracle", "DE Shaw"]

    return ScrollView {
        VStack(spacing: PPSpacing.md) {
            ForEach(names, id: \.self) { name in
                PPCard(padding: PPSpacing.md) {
                    HStack(spacing: PPSpacing.md) {
                        PPCompanyLogo(companyName: name)
                        Text(name).font(.ppBodyMedium)
                        Spacer()
                    }
                }
            }
        }
        .padding(PPSpacing.xl)
    }
    .foregroundStyle(Color.ppText)
    .ppScreenBackground()
}
