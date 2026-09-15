import SwiftUI

struct PPSegmentedChips<ID: Hashable>: View {

    enum Style {
        case wrapping
        case scrolling
    }

    struct Item: Identifiable {
        let id: ID
        let title: String
    }

    let items: [Item]
    @Binding var selection: ID
    var style: Style = .wrapping

    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch style {
            case .wrapping:
                FlowRow { chips }
            case .scrolling:
                ScrollView(.horizontal) {
                    HStack(spacing: PPSpacing.sm) { chips }
                }
                .scrollIndicators(.hidden)
            }
        }
        .animation(reduceMotion ? nil : PPMotion.settle, value: selection)
    }

    private var chips: some View {
        ForEach(items) { item in
            chip(item)
        }
    }

    private func chip(_ item: Item) -> some View {
        let isSelected = item.id == selection

        return Button {
            selection = item.id
        } label: {
            Text(item.title)
                .font(.ppCaption)
                .foregroundStyle(isSelected ? Color.ppOnAccent : Color.ppText)
                .padding(.horizontal, PPSpacing.lg)
                .frame(height: 36)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.ppAccent400)
                            .matchedGeometryEffect(id: "chip-highlight", in: highlight)
                    } else {
                        Capsule().strokeBorder(Color.ppBorderStrong, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Segmented chips") {
    @Previewable @State var topic: QuizTopic = .csFundamentals
    @Previewable @State var company = "google"

    VStack(alignment: .leading, spacing: PPSpacing.xxl) {
        PPSegmentedChips(
            items: QuizTopic.allCases.map { .init(id: $0, title: $0.displayName) },
            selection: $topic
        )

        PPSegmentedChips(
            items: SampleData.companies.map { .init(id: $0.slug, title: $0.name) },
            selection: $company,
            style: .scrolling
        )
    }
    .padding(PPSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .ppScreenBackground()
}
