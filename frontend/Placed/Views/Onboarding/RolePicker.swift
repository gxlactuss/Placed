import SwiftUI

struct RolePicker: View {

    @Binding var selection: CareerRole?
    var showsFamilyHeadings: Bool = true

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var badgeSide: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.xl) {
            ForEach(CareerRole.Family.allCases) { family in
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    if showsFamilyHeadings {
                        Text(family.title)
                            .ppSectionLabelStyle()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    grid(family.roles)
                }
            }
        }
    }

    /// Two columns with equal-height rows. An odd role out spans the full width as a
    /// row tile instead of leaving a hole; at accessibility sizes every tile is a row.
    private func grid(_ roles: [CareerRole]) -> some View {
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: roles.count, by: columns).map {
            Array(roles[$0..<min($0 + columns, roles.count)])
        }
        return Grid(horizontalSpacing: PPSpacing.md, verticalSpacing: PPSpacing.md) {
            ForEach(rows, id: \.first) { row in
                GridRow {
                    if row.count == columns, columns > 1 {
                        ForEach(row) { tile($0, isWide: false) }
                    } else {
                        tile(row[0], isWide: true).gridCellColumns(2)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ role: CareerRole, isWide: Bool) -> some View {
        let isSelected = selection == role
        return Button {
            withAnimation(PPMotion.snappy) { selection = role }
        } label: {
            Group {
                if isWide {
                    HStack(alignment: .center, spacing: PPSpacing.md) {
                        badge(role, isSelected: isSelected)
                        labels(role)
                        Spacer(minLength: 0)
                        check(isSelected)
                    }
                } else {
                    VStack(alignment: .leading, spacing: PPSpacing.md) {
                        HStack(alignment: .top) {
                            badge(role, isSelected: isSelected)
                            Spacer(minLength: 0)
                            check(isSelected)
                        }
                        labels(role)
                    }
                }
            }
            .padding(PPSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                isSelected ? Color.ppAccentSection : Color.ppSurface,
                in: .rect(cornerRadius: PPRadius.xl)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.xl)
                    .strokeBorder(
                        isSelected ? Color.ppAccent : Color.ppBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(.rect(cornerRadius: PPRadius.xl))
        }
        .buttonStyle(.ppPressable)
        .accessibilityLabel(Text(role.title))
        .accessibilityHint(Text(role.blurb))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func badge(_ role: CareerRole, isSelected: Bool) -> some View {
        Image(systemName: role.icon)
            .font(.system(size: badgeSide * 0.45, weight: .medium))
            .foregroundStyle(isSelected ? Color.ppOnAccent : Color.ppAccent400)
            .frame(width: badgeSide, height: badgeSide)
            .background(
                isSelected ? Color.ppAccent : Color.ppElevated,
                in: .rect(cornerRadius: PPRadius.md)
            )
            .accessibilityHidden(true)
    }

    private func labels(_ role: CareerRole) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.xs) {
            Text(role.shortTitle)
                .font(.ppHeadline)
                .foregroundStyle(Color.ppText)
            Text(role.blurb)
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
    }

    private func check(_ isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.ppHeadline)
            .foregroundStyle(isSelected ? Color.ppAccent : Color.ppBorderStrong)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
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
