import SwiftUI

struct RolePicker: View {

    @Binding var selection: CareerRole?
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
            .padding(PPSpacing.md)
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
