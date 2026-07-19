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
