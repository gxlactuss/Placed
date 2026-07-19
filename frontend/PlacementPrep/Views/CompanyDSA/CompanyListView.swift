import SwiftUI

/// Company-wise DSA problem list with search, company filter and local solved state.
struct CompanyListView: View {

    @State private var selectedSlug = "google"
    @State private var query = ""
    /// Solved problems are held in memory only for now; persist once the API exists.
    @State private var solved: Set<String> = [
        "https://leetcode.com/problems/two-sum",
        "https://leetcode.com/problems/longest-substring-without-repeating-characters",
        "https://leetcode.com/problems/trapping-rain-water",
    ]

    var body: some View {
        VStack(spacing: PPSpacing.lg) {
            header

            if filteredProblems.isEmpty {
                emptyState
            } else {
                problemList
            }
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: PPSpacing.lg) {
            Text("Companies")
                .font(.ppDisplay)
                .frame(maxWidth: .infinity, alignment: .leading)

            PPSearchField(placeholder: "Search problems or companies", text: $query)

            ScrollView(.horizontal) {
                HStack(spacing: PPSpacing.sm) {
                    ForEach(SampleData.companies) { company in
                        PPFilterChip(
                            title: company.name,
                            isSelected: company.slug == selectedSlug
                        ) {
                            selectedSlug = company.slug
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            summaryRow
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.lg)
    }

    private var summaryRow: some View {
        HStack {
            Text("\(selectedCompany.name) · \(solvedCount) / \(allProblems.count) solved")
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)

            Spacer()

            HStack(spacing: PPSpacing.sm) {
                ForEach(PPDifficulty.allCases) { level in
                    Text("\(solvedCount(for: level))/\(total(for: level)) \(level.initial)")
                        .font(.ppMicro)
                        .foregroundStyle(level.color)
                }
            }
        }
    }

    // MARK: - List

    private var problemList: some View {
        ScrollView {
            LazyVStack(spacing: PPSpacing.md) {
                ForEach(filteredProblems) { problem in
                    problemRow(problem)
                }
            }
            .padding(.horizontal, PPSpacing.xl)
            .padding(.bottom, PPSpacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    private func problemRow(_ problem: DSAQuestion) -> some View {
        let isSolved = solved.contains(problem.id)

        return PPCard {
            HStack(spacing: PPSpacing.md) {
                PPCheckbox(
                    isOn: Binding(
                        get: { isSolved },
                        set: { newValue in
                            if newValue { solved.insert(problem.id) } else { solved.remove(problem.id) }
                        }
                    )
                )

                VStack(alignment: .leading, spacing: PPSpacing.sm) {
                    Text(problem.title)
                        .font(.ppBodyMedium)
                        .strikethrough(isSolved, color: .ppMuted)
                        .foregroundStyle(isSolved ? Color.ppMuted : Color.ppText)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: PPSpacing.sm) {
                        PPBadge(difficulty(of: problem))
                        if let frequency = problem.frequency {
                            Text("Freq \(Int(frequency * 100))%")
                                .font(.ppMicro)
                                .foregroundStyle(Color.ppMuted)
                        }
                    }
                }

                Spacer(minLength: PPSpacing.sm)

                // Not force-unwrapped: these URLs come from the API once it is
                // wired up, and a malformed one must not take the screen down.
                if let url = URL(string: problem.leetcodeURL) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(Color.ppMuted)
                            .frame(width: 32, height: 32)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Open \(problem.title) on LeetCode")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: PPSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Color.ppMuted)
            Text("No problems match \"\(query)\"")
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PPSpacing.xl)
    }

    // MARK: - Data

    private var selectedCompany: CompanySummary {
        SampleData.companies.first { $0.slug == selectedSlug } ?? SampleData.companies[0]
    }

    private var allProblems: [DSAQuestion] {
        SampleData.problems(for: selectedSlug)
    }

    private var filteredProblems: [DSAQuestion] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return allProblems }
        return allProblems.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var solvedCount: Int {
        allProblems.filter { solved.contains($0.id) }.count
    }

    private func difficulty(of problem: DSAQuestion) -> PPDifficulty {
        PPDifficulty(rawValue: problem.difficulty.lowercased()) ?? .medium
    }

    private func total(for level: PPDifficulty) -> Int {
        allProblems.filter { difficulty(of: $0) == level }.count
    }

    private func solvedCount(for level: PPDifficulty) -> Int {
        allProblems.filter { difficulty(of: $0) == level && solved.contains($0.id) }.count
    }
}

#Preview {
    CompanyListView()
}
