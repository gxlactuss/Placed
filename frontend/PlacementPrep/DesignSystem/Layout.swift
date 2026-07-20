import SwiftUI

/// Vertical and horizontal rhythm. Screens use `.xl` as their outer gutter.
enum PPSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
}

/// Corner radii. Controls use `.md`, cards use `.lg`. Deliberately tight —
/// blobby corners read as template; these read as drawn.
enum PPRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let pill: CGFloat = 999
}

enum PPSize {
    /// Minimum height for buttons, search fields and other tap targets.
    static let control: CGFloat = 52
    static let iconTile: CGFloat = 44
    static let checkbox: CGFloat = 24
}

/// The app's two animation curves. Everything animates with one of these so
/// motion feels like a single system, and both are plain springs — no layout
/// thrash, no continuous effects, nothing that keeps the CPU awake.
enum PPMotion {
    /// Press feedback and small state flips.
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.75)
    /// Selection moves and content transitions.
    static let settle = Animation.spring(response: 0.4, dampingFraction: 0.8)
}


/// Minimal wrapping row. `LazyVGrid` cannot size columns to their content, and
/// the chip rows here need to wrap on smaller widths and at larger text sizes.
struct FlowRow: Layout {

    var spacing: CGFloat = PPSpacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        return CGSize(width: maxWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
