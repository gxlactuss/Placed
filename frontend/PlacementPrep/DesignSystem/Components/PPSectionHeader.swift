import SwiftUI

/// Uppercased group label above a stack of cards, e.g. "PRACTICE MODES".
/// The optional accessory sits on the trailing edge.
struct PPSectionHeader<Accessory: View>: View {

    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack {
            Text(title).ppSectionLabelStyle()
            Spacer(minLength: PPSpacing.md)
            accessory
        }
    }
}

extension PPSectionHeader where Accessory == EmptyView {
    init(_ title: String) {
        self.title = title
        self.accessory = EmptyView()
    }
}

#Preview("Section header") {
    VStack(alignment: .leading, spacing: PPSpacing.xl) {
        PPSectionHeader("Practice modes")

        PPSectionHeader(title: "Areas to improve") {
            Button("See all") {}
                .buttonStyle(.ppGhost)
        }
    }
    .padding(PPSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .ppScreenBackground()
}
