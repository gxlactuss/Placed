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

/// Corner radii. Controls use `.md`, cards use `.lg`.
enum PPRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 18
    static let xl: CGFloat = 24
    static let pill: CGFloat = 999
}

enum PPSize {
    /// Minimum height for buttons, search fields and other tap targets.
    static let control: CGFloat = 52
    static let iconTile: CGFloat = 44
    static let checkbox: CGFloat = 24
}
