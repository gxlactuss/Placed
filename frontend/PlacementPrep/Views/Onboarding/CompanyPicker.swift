import SwiftUI

/// Picks the one company the user is preparing for, then shows what that company asks most.
struct CompanyPicker: View {

    enum Choice: Hashable {
        case company(DSACompany)
        case other
    }

    @Binding var choice: Choice?
    @Binding var otherName: String

    @Environment(CompanyBank.self) private var bank
    @State private var query = ""
    @State private var profile: CompanyProfile?

    private let columns = [
        GridItem(.flexible(), spacing: PPSpacing.md),
        GridItem(.flexible(), spacing: PPSpacing.md)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.lg) {
            if let choice {
                selected(choice)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                grid
                    .transition(.opacity)
            }
        }
        .animation(PPMotion.settle, value: choice)
        .task(id: choice) { await loadProfile() }
    }

    // MARK: - Picking

    private var grid: some View {
        VStack(alignment: .leading, spacing: PPSpacing.lg) {
            PPSearchField(placeholder: "Search companies", text: $query)

            LazyVGrid(columns: columns, spacing: PPSpacing.md) {
                ForEach(filtered) { company in
                    tile(title: company.name, isKJSIT: company.isKJSITRecruiter) {
                        PPCompanyLogo(companyName: company.name, size: 28)
                    } action: {
                        pick(.company(company))
                    }
                }
                tile(title: "Other / not listed", isKJSIT: false) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.ppMuted)
                        .frame(width: 28, height: 28)
                } action: {
                    if otherName.isEmpty { otherName = query.trimmingCharacters(in: .whitespaces) }
                    pick(.other)
                }
            }
        }
    }

    private func tile<Icon: View>(
        title: String,
        isKJSIT: Bool,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: PPSpacing.sm) {
                icon()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.ppBodyMedium)
                        .foregroundStyle(Color.ppText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                    if isKJSIT {
                        Text("Visits KJSIT")
                            .font(.ppMicro)
                            .foregroundStyle(Color.ppEasy)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(PPSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.lg)
                    .strokeBorder(Color.ppBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.ppPressable)
    }

    private var filtered: [DSACompany] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matches = trimmed.isEmpty
            ? bank.companies
            : bank.companies.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        return matches.sorted { lhs, rhs in
            if lhs.isKJSITRecruiter != rhs.isKJSITRecruiter { return lhs.isKJSITRecruiter }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Picked

    @ViewBuilder
    private func selected(_ choice: Choice) -> some View {
        HStack(spacing: PPSpacing.md) {
            switch choice {
            case .company(let company):
                PPCompanyLogo(companyName: company.name, size: 36)
                Text(company.name).font(.ppHeadline)
            case .other:
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.ppMuted)
                Text("Other").font(.ppHeadline)
            }
            Spacer(minLength: PPSpacing.sm)
            Button("Change") { pick(nil) }
                .buttonStyle(.ppInlineLink)
        }

        if choice == .other {
            PPTextField(
                label: "Company name (optional)",
                placeholder: "e.g. Deutsche Bank",
                text: $otherName,
                autocapitalization: .words,
                submitLabel: .done
            )
        }

        if let profile {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text(profile.isGeneral ? "What interviews ask" : "What they ask most")
                    .ppSectionLabelStyle()
                CompanyInsightCard(profile: profile, unlistedName: unlistedName)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            ProgressView()
                .tint(Color.ppMuted)
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private var unlistedName: String? {
        let trimmed = otherName.trimmingCharacters(in: .whitespaces)
        return choice == .other && !trimmed.isEmpty ? trimmed : nil
    }

    private func pick(_ next: Choice?) {
        PPHaptics.light()
        query = ""
        choice = next
    }

    private func loadProfile() async {
        switch choice {
        case .company(let company):
            let loaded = await bank.profile(for: company)
            withAnimation(PPMotion.settle) { profile = loaded }
        case .other:
            await bank.loadCatalogIfNeeded()
            withAnimation(PPMotion.settle) { profile = bank.generalProfile }
        case nil:
            profile = nil
        }
    }
}

#Preview {
    @Previewable @State var choice: CompanyPicker.Choice?
    @Previewable @State var other = ""
    ScrollView {
        CompanyPicker(choice: $choice, otherName: $other).padding(PPSpacing.xl)
    }
    .foregroundStyle(Color.ppText)
    .ppScreenBackground()
    .environment(CompanyBank())
}
