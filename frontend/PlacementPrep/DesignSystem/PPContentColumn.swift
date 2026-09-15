import SwiftUI

extension View {
    func ppContentColumn(_ width: CGFloat = PPSize.contentColumn) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
    }
}

extension PPSize {
    static let contentColumn: CGFloat = 640

    static let wideColumn: CGFloat = 980
}

struct PPAdaptiveColumns: DynamicProperty {

    @Environment(\.horizontalSizeClass) private var sizeClass

    var count: Int { sizeClass == .regular ? 2 : 1 }

    func grid(spacing: CGFloat = PPSpacing.md) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}

#Preview("Content column") {
    ScrollView {
        VStack(spacing: PPSpacing.md) {
            ForEach(0..<4, id: \.self) { index in
                PPCard {
                    Text("Card \(index + 1) — held to \(Int(PPSize.contentColumn))pt however wide the screen is")
                        .font(.ppBody)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(PPSpacing.xl)
        .ppContentColumn()
    }
    .foregroundStyle(Color.ppText)
    .ppScreenBackground()
}
