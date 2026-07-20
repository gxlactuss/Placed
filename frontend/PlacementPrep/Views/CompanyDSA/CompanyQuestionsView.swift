import SwiftUI

/// One company's question list: progress summary, difficulty filter, search,
/// and a checkbox per row that persists via `SolvedStore`.
struct CompanyQuestionsView: View {

    let company: DSACompany

    @Environment(CompanyBank.self) private var bank
    @Environment(SolvedStore.self) private var solved

    @State private var problems: [DSAProblem] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var difficultyFilter: DifficultyFilter = .all

    /// `DSADifficulty` plus an "All" case, so the filter can be one chip group.
    enum DifficultyFilter: Hashable, CaseIterable {
        case all, easy, medium, hard

        var title: String {
            switch self {
            case .all: "All"
            case .easy: "Easy"
            case .medium: "Medium"
            case .hard: "Hard"
            }
        }

        var difficulty: DSADifficulty? {
            switch self {
            case .all: nil
            case .easy: .easy
            case .medium: .medium
            case .hard: .hard
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.ppMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle(company.name)
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .task(id: company.id) {
            isLoading = true
            problems = await bank.problems(for: company)
            isLoading = false
        }
    }

    private var content: some View {
        VStack(spacing: PPSpacing.lg) {
            header

            if visible.isEmpty {
                Text("No problems match this filter")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rows
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: PPSpacing.lg) {
            PPSearchField(placeholder: "Search problems", text: $query)

            PPSegmentedChips(
                items: DifficultyFilter.allCases.map { .init(id: $0, title: $0.title) },
                selection: $difficultyFilter,
                style: .scrolling
            )

            progressSummary
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.md)
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            HStack {
                Text("\(solvedTotal) / \(problems.count) solved")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)

                Spacer()

                HStack(spacing: PPSpacing.sm) {
                    ForEach(DSADifficulty.allCases) { level in
                        Text("\(solvedCount(for: level))/\(total(for: level)) \(level.initial)")
                            .font(.ppMicro)
                            .foregroundStyle(level.accent)
                    }
                }
            }

            PPProgressBar(
                progress: problems.isEmpty ? 0 : Double(solvedTotal) / Double(problems.count)
            )
        }
    }

    // MARK: - Rows

    private var rows: some View {
        ScrollView {
            LazyVStack(spacing: PPSpacing.md) {
                ForEach(visible) { problem in
                    row(problem)
                }
            }
            .padding(.horizontal, PPSpacing.xl)
            .padding(.bottom, PPSpacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ problem: DSAProblem) -> some View {
        let isSolved = solved.isSolved(problem.id)

        return PPCard {
            HStack(spacing: PPSpacing.md) {
                PPCheckbox(
                    isOn: Binding(
                        get: { isSolved },
                        set: { _ in solved.toggle(problem.id) }
                    )
                )

                VStack(alignment: .leading, spacing: PPSpacing.sm) {
                    Text(problem.title)
                        .font(.ppBodyMedium)
                        .strikethrough(isSolved, color: .ppMuted)
                        .foregroundStyle(isSolved ? Color.ppMuted : Color.ppText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: PPSpacing.sm) {
                        PPBadge(problem.difficulty.title, tone: .tinted(problem.difficulty.accent))
                        if problem.frequency > 0 {
                            Text("Freq \(Int(problem.frequency.rounded()))")
                                .font(.ppMicro)
                                .foregroundStyle(Color.ppMuted)
                        }
                    }
                }

                Spacer(minLength: PPSpacing.sm)

                if let url = problem.url {
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

    // MARK: - Derived

    private var visible: [DSAProblem] {
        var result = problems

        if let level = difficultyFilter.difficulty {
            result = result.filter { $0.difficulty == level }
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
                    || $0.topics.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
        }

        return result
    }

    private var solvedTotal: Int { solved.solvedCount(in: problems) }

    private func total(for level: DSADifficulty) -> Int {
        problems.count { $0.difficulty == level }
    }

    private func solvedCount(for level: DSADifficulty) -> Int {
        solved.solvedCount(in: problems.filter { $0.difficulty == level })
    }
}

extension DSADifficulty {
    /// Maps onto the design system's difficulty palette.
    var accent: Color {
        switch self {
        case .easy: .ppEasy
        case .medium: .ppMedium
        case .hard: .ppHard
        }
    }
}

#Preview {
    NavigationStack {
        CompanyQuestionsView(
            company: DSACompany(
                name: "Google",
                fileURL: Bundle.main.url(forResource: "Google", withExtension: "csv", subdirectory: "Companies")
                    ?? Bundle.main.url(forResource: "Google", withExtension: "csv")
                    ?? URL(filePath: "/dev/null")
            )
        )
    }
    .environment(CompanyBank())
    .environment(SolvedStore.preview(solved: ["two-sum"]))
}
