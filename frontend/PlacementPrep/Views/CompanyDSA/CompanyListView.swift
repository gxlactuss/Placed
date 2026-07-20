import SwiftUI

/// Company picker: a searchable list of every company with a bundled CSV.
/// Selecting one pushes its question list.
struct CompanyListView: View {

    @Environment(CompanyBank.self) private var bank
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if bank.companies.isEmpty {
                    missingDataState
                } else if filtered.isEmpty {
                    noMatchState
                } else {
                    list
                }
            }
            .navigationTitle("LeetCode")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search companies"
            )
            .foregroundStyle(Color.ppText)
            .ppScreenBackground()
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: PPSpacing.sm) {
                ForEach(filtered) { company in
                    NavigationLink(value: company) {
                        PPCard(padding: PPSpacing.md) {
                            HStack(spacing: PPSpacing.md) {
                                PPIconTile(systemName: "building.2", size: 36)

                                Text(company.name)
                                    .font(.ppBodyMedium)
                                    .foregroundStyle(Color.ppText)

                                Spacer(minLength: PPSpacing.sm)

                                Image(systemName: "chevron.right")
                                    .font(.ppMicro)
                                    .foregroundStyle(Color.ppMuted)
                            }
                        }
                    }
                    .buttonStyle(.ppPressable)
                }
            }
            .padding(.horizontal, PPSpacing.xl)
            .padding(.bottom, PPSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .navigationDestination(for: DSACompany.self) { company in
            CompanyQuestionsView(company: company)
        }
    }

    private var filtered: [DSACompany] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return bank.companies }
        return bank.companies.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var noMatchState: some View {
        emptyState(
            icon: "magnifyingglass",
            title: "No companies match \"\(query)\"",
            detail: nil
        )
    }

    /// Shown when no CSVs made it into the bundle — far more useful than an
    /// empty list, since the likely cause is a setup step being missed.
    private var missingDataState: some View {
        emptyState(
            icon: "tray",
            title: "No company data bundled",
            detail: "Add the company CSVs to Resources/Companies, then run xcodegen generate."
        )
    }

    private func emptyState(icon: String, title: String, detail: String?) -> some View {
        VStack(spacing: PPSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Color.ppMuted)
            Text(title)
                .font(.ppBodyMedium)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PPSpacing.xxl)
    }
}

#Preview {
    CompanyListView()
        .environment(CompanyBank())
        .environment(SolvedStore.preview())
}
