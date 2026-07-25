import SwiftUI

/// The vendor sign-in marks: Google's four-colour "G" and GitHub's Invertocat.
///
/// Drawn as vector paths rather than bundled PNGs so they stay sharp at any size
/// and scale with Dynamic Type alongside the button label they sit next to.
///
/// This is the one deliberate exception to "screens never hardcode colour":
/// Google's brand terms don't permit recolouring the "G", so its four hues are
/// literals here instead of palette tokens. GitHub's mark *is* monochrome and
/// takes a `tint`, so it defaults to `ppText` and inverts correctly on the light
/// themes.
struct PPBrandMark: View {

    enum Provider {
        case google
        case github
    }

    let provider: Provider
    /// Applies to monochrome marks only — Google's "G" ignores it by design.
    var tint: Color = .ppText
    var size: CGFloat = 18

    /// Tracks the text size so the mark keeps pace with the label beside it.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Group {
            switch provider {
            case .google: google
            case .github: github
            }
        }
        .frame(width: size * scale, height: size * scale)
        .accessibilityHidden(true)  // the button's own label already names the provider
    }

    // The "G" is four separate wedges, each its own flat colour — no gradients,
    // which is also why it sits comfortably in this design system.
    private var google: some View {
        ZStack {
            VectorMark(BrandPath.googleBlue, viewBox: 48).fill(Color(hex: 0x4285F4))
            VectorMark(BrandPath.googleGreen, viewBox: 48).fill(Color(hex: 0x34A853))
            VectorMark(BrandPath.googleYellow, viewBox: 48).fill(Color(hex: 0xFBBC05))
            VectorMark(BrandPath.googleRed, viewBox: 48).fill(Color(hex: 0xEA4335))
        }
    }

    private var github: some View {
        VectorMark(BrandPath.github, viewBox: 24).fill(tint)
    }
}

// MARK: - Path data

/// Official mark geometry, as SVG path data in its own viewBox.
private enum BrandPath {
    static let googleBlue = """
        M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17z
        """
    static let googleGreen = """
        M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46z
        """
    static let googleYellow = """
        M11.69 28.18C11.25 26.86 11 25.45 11 24s.25-2.86.69-4.18v-5.7H4.34C2.85 17.09 2 20.45 2 24s.85 6.91 2.34 9.88l7.35-5.7z
        """
    static let googleRed = """
        M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z
        """
    static let github = """
        M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04\
        -3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236\
        1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22\
        -.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405\
        2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92\
        .42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12z
        """
}

// MARK: - Vector shape

/// A `Shape` built from SVG path data, scaled to fit its frame.
private struct VectorMark: Shape {

    private let data: String
    private let viewBox: CGFloat

    init(_ data: String, viewBox: CGFloat) {
        self.data = data
        self.viewBox = viewBox
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / viewBox
        // Centre the (square) mark in whatever frame it was handed.
        let transform = CGAffineTransform(translationX: (rect.width - side) / 2,
                                          y: (rect.height - side) / 2)
            .scaledBy(x: scale, y: scale)
        return Self.parse(data).applying(transform)
    }

    /// Minimal SVG path-data reader — `M L H V C S Z`, absolute and relative,
    /// which is everything the two marks above use (no arcs, no exponents).
    /// Hand-rolled for the same reason `CSVParser` is: a dependency isn't worth
    /// ~80 lines of scanning. SVG and SwiftUI agree on y-down, so no flip.
    private static func parse(_ data: String) -> Path {
        var path = Path()
        let chars = Array(data)
        var i = 0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        /// Second control point of the previous curve — `S` reflects it.
        var lastControl: CGPoint?
        var command: Character = "M"

        func skipSeparators() {
            while i < chars.count, chars[i] == "," || chars[i].isWhitespace { i += 1 }
        }

        func number() -> CGFloat {
            skipSeparators()
            var text = ""
            if i < chars.count, chars[i] == "-" || chars[i] == "+" {
                text.append(chars[i])
                i += 1
            }
            while i < chars.count, chars[i].isNumber || chars[i] == "." {
                // "1.5.5" is two numbers, so a second dot ends this one.
                if chars[i] == ".", text.contains(".") { break }
                text.append(chars[i])
                i += 1
            }
            return CGFloat(Double(text) ?? 0)
        }

        while i < chars.count {
            skipSeparators()
            guard i < chars.count else { break }

            if chars[i].isLetter {
                command = chars[i]
                i += 1
            } else if !(chars[i].isNumber || chars[i] == "-" || chars[i] == "+" || chars[i] == ".") {
                i += 1  // unrecognised byte: step over it rather than spin
                continue
            }
            // Otherwise the previous command simply repeats with fresh operands.

            let isRelative = command.isLowercase
            // Relative operands are all measured from the point the command
            // started at, so this reads `current` before any of them land.
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                isRelative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch Character(command.uppercased()) {
            case "M":
                let target = point(number(), number())
                path.move(to: target)
                current = target
                subpathStart = target
                lastControl = nil
                // Further coordinate pairs after a moveto are implicit linetos.
                command = isRelative ? "l" : "L"

            case "L":
                let target = point(number(), number())
                path.addLine(to: target)
                current = target
                lastControl = nil

            case "H":
                let x = number()
                let target = CGPoint(x: isRelative ? current.x + x : x, y: current.y)
                path.addLine(to: target)
                current = target
                lastControl = nil

            case "V":
                let y = number()
                let target = CGPoint(x: current.x, y: isRelative ? current.y + y : y)
                path.addLine(to: target)
                current = target
                lastControl = nil

            case "C":
                let control1 = point(number(), number())
                let control2 = point(number(), number())
                let target = point(number(), number())
                path.addCurve(to: target, control1: control1, control2: control2)
                current = target
                lastControl = control2

            case "S":
                let control2 = point(number(), number())
                let target = point(number(), number())
                let control1 = lastControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                path.addCurve(to: target, control1: control1, control2: control2)
                current = target
                lastControl = control2

            case "Z":
                path.closeSubpath()
                current = subpathStart
                lastControl = nil

            default:
                break
            }
        }
        return path
    }
}

#Preview("Brand marks") {
    VStack(spacing: PPSpacing.lg) {
        // At button size, beside a label.
        Button {} label: {
            Label { Text("Continue with Google") } icon: { PPBrandMark(provider: .google) }
        }
        .buttonStyle(.ppSecondary)

        Button {} label: {
            Label { Text("Continue with GitHub") } icon: { PPBrandMark(provider: .github) }
        }
        .buttonStyle(.ppSecondary)

        // Blown up, to check the geometry.
        HStack(spacing: PPSpacing.xl) {
            PPBrandMark(provider: .google, size: 64)
            PPBrandMark(provider: .github, size: 64)
            PPBrandMark(provider: .github, tint: .ppAccent, size: 64)
        }
        .padding(.top, PPSpacing.xl)
    }
    .padding(PPSpacing.xl)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
