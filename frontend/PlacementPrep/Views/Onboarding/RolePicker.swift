import SwiftUI

/// Grid of the roles a student can prepare for.
///
/// Shared by onboarding and the interview setup screen so the two can never
/// disagree about what a role is — before this, both took free text and the
/// interview screen had to reconcile two spellings of the same job.
///
/// Grouped by family rather than presented as one 16-item list: the roles a
/// student is choosing between are almost always in the same family, and a flat
/// list of that length is read as a wall.
struct RolePicker: View {

    @Binding var selection: CareerRole?
    /// Set when the picker is the whole screen rather than one section of it.
    var showsFamilyHeadings: Bool = true

    private let columns = [
        GridItem(.flexible(), spacing: PPSpacing.md),
        GridItem(.flexible(), spacing: PPSpacing.md)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.lg) {
            ForEach(CareerRole.Family.allCases) { family in
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    if showsFamilyHeadings {
                        Text(family.title).ppSectionLabelStyle()
                    }
                    LazyVGrid(columns: columns, spacing: PPSpacing.md) {
                        ForEach(family.roles) { role in
                            card(role)
                        }
                    }
                }
            }
        }
    }

    private func card(_ role: CareerRole) -> some View {
        let isSelected = selection == role
        return Button {
            withAnimation(PPMotion.snappy) { selection = role }
        } label: {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                // Semantic, not a fixed point size: everything else in the card
                // scales with Dynamic Type, and a frozen icon beside growing text
                // is what makes the row look off before it looks too small.
                Image(systemName: role.icon)
                    .font(.ppHeadline)
                    .foregroundStyle(isSelected ? Color.ppAccent : Color.ppMuted)
                Text(role.title)
                    .font(.ppBodyMedium)
                    .foregroundStyle(Color.ppText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(role.blurb)
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Padding first, then the frame. The other order sizes the *content*
            // to the full column width and then adds 12pt of padding outside it,
            // so every card overflows its column by 24pt and the right-hand
            // column runs off screen.
            .padding(PPSpacing.md)
            // `maxHeight` is what keeps a row even. A grid row is as tall as its
            // tallest cell, but a shorter card does not stretch to meet it on its
            // own — so "Java / Spring Developer" wrapping to two lines left the
            // card beside it visibly short. `minHeight` is only a floor for the
            // rows where every title fits on one line.
            .frame(
                maxWidth: .infinity,
                minHeight: 104,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.lg)
                    .strokeBorder(
                        isSelected ? Color.ppAccent : Color.ppBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Nothing picked") {
    struct Harness: View {
        @State private var role: CareerRole?
        var body: some View {
            ScrollView {
                RolePicker(selection: $role).padding(PPSpacing.xl)
            }
            .ppScreenBackground()
        }
    }
    return Harness()
}

#Preview("One picked") {
    struct Harness: View {
        @State private var role: CareerRole? = .ios
        var body: some View {
            ScrollView {
                RolePicker(selection: $role).padding(PPSpacing.xl)
            }
            .ppScreenBackground()
        }
    }
    return Harness()
}
