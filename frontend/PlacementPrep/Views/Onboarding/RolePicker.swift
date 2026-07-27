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
                Image(systemName: role.icon)
                    .font(.system(size: 18, weight: .regular))
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
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(PPSpacing.md)
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
