import SwiftUI

/// Company picker: a searchable list of every company with a bundled CSV.
/// Selecting one pushes its question list.
struct CompanyListView: View {

    @Environment(CompanyBank.self) private var bank
    @Environment(SolvedStore.self) private var solved
    @State private var query = ""
    // Not `private`: a private stored property makes the memberwise
    // initializer private too, and this view is constructed by name.
    var columns = PPAdaptiveColumns()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                if bank.companies.isEmpty {
                    missingDataState
                } else if filtered.isEmpty {
                    noMatchState
                } else {
                    list
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .foregroundStyle(Color.ppText)
            .ppScreenBackground()
            .task { await bank.loadCatalogIfNeeded() }
        }
    }

    /// Serif header plus the in-house search field, matching the rest of the app.
    /// A system `.searchable` bar would render in SF and reserve nav-bar space.
    private var header: some View {
        VStack(alignment: .leading, spacing: PPSpacing.lg) {
            Text("LeetCode").font(.ppDisplay)
            overviewCard
            PPSearchField(placeholder: "Search companies", text: $query)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.lg)
        .padding(.bottom, PPSpacing.md)
        // Same width as the grid below, so the title, the overview card and the
        // first column of companies all start on one line.
        .ppContentColumn(PPSize.wideColumn)
    }

    /// Combined progress across every distinct problem in the bank. Deduped by
    /// slug in `CompanyBank.catalog`, so solving "Two Sum" advances this once no
    /// matter how many company lists carry it.
    private var overviewCard: some View {
        PPCard(padding: PPSpacing.lg) {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Overall progress").font(.ppBodyMedium)
                    Spacer()
                    if bank.isCatalogReady {
                        Text("\(stats.solved) / \(stats.total) solved")
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                            .contentTransition(.numericText())
                    }
                }

                PPProgressBar(
                    progress: stats.total == 0 ? 0 : Double(stats.solved) / Double(stats.total)
                )

                if bank.isCatalogReady {
                    HStack(spacing: PPSpacing.lg) {
                        ForEach(DSADifficulty.allCases) { level in
                            HStack(spacing: 5) {
                                Circle().fill(level.accent).frame(width: 7, height: 7)
                                Text("\(stats.solvedByLevel[level, default: 0])/\(bank.catalogTotals[level, default: 0]) \(level.title)")
                                    .font(.ppMicro)
                                    .foregroundStyle(Color.ppMuted)
                            }
                        }
                    }
                } else {
                    Text("Calculating…")
                        .font(.ppMicro)
                        .foregroundStyle(Color.ppMuted)
                }
            }
        }
    }

    /// Roughly 38 companies, each a logo and a name — the row that most wants a
    /// second column when there is width for one.
    private var list: some View {
        ScrollView {
            LazyVGrid(columns: columns.grid(spacing: PPSpacing.sm), spacing: PPSpacing.sm) {
                ForEach(filtered) { company in
                    NavigationLink(value: company) {
                        PPCard(padding: PPSpacing.md) {
                            HStack(spacing: PPSpacing.md) {
                                PPCompanyLogo(companyName: company.name)

                                Text(company.name)
                                    .font(.ppBodyMedium)
                                    .foregroundStyle(Color.ppText)

                                if company.isKJSITRecruiter {
                                    PPBadge("KJSIT", tone: .tinted(.ppEasy))
                                }

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
            .ppContentColumn(PPSize.wideColumn)
        }
        .scrollIndicators(.hidden)
        .navigationDestination(for: DSACompany.self) { company in
            CompanyQuestionsView(company: company)
        }
    }

    /// One pass over the deduped catalog: total, solved, and solved-per-level.
    private var stats: (total: Int, solved: Int, solvedByLevel: [DSADifficulty: Int]) {
        var solvedByLevel: [DSADifficulty: Int] = [:]
        var solvedTotal = 0
        for (slug, level) in bank.catalog where solved.isSolved(slug) {
            solvedTotal += 1
            solvedByLevel[level, default: 0] += 1
        }
        return (bank.catalog.count, solvedTotal, solvedByLevel)
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
