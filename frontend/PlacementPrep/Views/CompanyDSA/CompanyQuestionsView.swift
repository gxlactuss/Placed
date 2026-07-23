import SwiftUI

/// One company's question list: progress summary, difficulty filter, search,
/// and a checkbox per row that persists via `SolvedStore`.
struct CompanyQuestionsView: View {

    let company: DSACompany

    @Environment(CompanyBank.self) private var bank
    @Environment(SolvedStore.self) private var solved

    @State private var problems: [DSAProblem] = []
    @State private var availableTopics: [TopicCount] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var difficultyFilter: DifficultyFilter = .all
    /// Opt-in topic filter. Empty by default and never shown on the rows
    /// themselves — many people would rather not see a problem's category before
    /// they solve it.
    @State private var topicFilter: Set<String> = []
    @State private var showTopicSheet = false

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
            topicFilter = []
            let loaded = await bank.problems(for: company)
            problems = loaded
            availableTopics = Self.topics(in: loaded)
            isLoading = false
        }
        .sheet(isPresented: $showTopicSheet) {
            TopicFilterSheet(topics: availableTopics, selection: $topicFilter)
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

            HStack(spacing: PPSpacing.sm) {
                PPSegmentedChips(
                    items: DifficultyFilter.allCases.map { .init(id: $0, title: $0.title) },
                    selection: $difficultyFilter,
                    style: .scrolling
                )
                topicFilterButton
            }

            if !topicFilter.isEmpty {
                activeTopicChips
            }

            progressSummary
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.md)
    }

    /// Subtle funnel that opens the topic sheet. Deliberately understated and
    /// disabled when the data carries no topics, so it stays out of the way for
    /// anyone who never wants to filter.
    private var topicFilterButton: some View {
        Button { showTopicSheet = true } label: {
            HStack(spacing: PPSpacing.xs) {
                Image(systemName: "line.3.horizontal.decrease")
                if !topicFilter.isEmpty {
                    Text("\(topicFilter.count)")
                }
            }
            .font(.ppCaption)
            .foregroundStyle(topicFilter.isEmpty ? Color.ppMuted : Color.ppOnAccent)
            .padding(.horizontal, PPSpacing.md)
            .frame(height: 36)
            .background {
                if topicFilter.isEmpty {
                    Capsule().strokeBorder(Color.ppBorderStrong, lineWidth: 1)
                } else {
                    Capsule().fill(Color.ppAccent400)
                }
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(availableTopics.isEmpty)
        .accessibilityLabel("Filter by topic")
    }

    /// The active topic filters, each removable. Only appears once the user has
    /// opted in, so topics never surface unprompted.
    private var activeTopicChips: some View {
        FlowRow(spacing: PPSpacing.sm) {
            ForEach(topicFilter.sorted(), id: \.self) { topic in
                Button {
                    withAnimation(PPMotion.snappy) { _ = topicFilter.remove(topic) }
                } label: {
                    HStack(spacing: PPSpacing.xs) {
                        Text(topic)
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppAccent300)
                    .padding(.horizontal, PPSpacing.sm)
                    .frame(height: 28)
                    .background(Color.ppAccentSection, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(topic) filter")
            }
        }
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
        ProblemListScroll(problems: visible) { problem in
            row(problem)
        }
    }

    private func row(_ problem: DSAProblem) -> some View {
        let isSolved = solved.isSolved(problem.id)

        return PPCard {
            HStack(spacing: PPSpacing.md) {
                PPCheckbox(
                    isOn: Binding(
                        get: { isSolved },
                        set: { _ in
                            // Animate so the row slides down to the solved
                            // section (or back up) rather than jumping.
                            withAnimation(PPMotion.settle) { solved.toggle(problem.id) }
                        }
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

        // Union filter: a problem matches if it carries any of the chosen topics.
        if !topicFilter.isEmpty {
            result = result.filter { problem in
                problem.topics.contains { topicFilter.contains($0) }
            }
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
                    || $0.topics.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
        }

        // Solved problems sink to the bottom, keeping the app-wide "done, move
        // on" feel. Each group stays in its original frequency order — the
        // enumerated offset is a stable tiebreaker, since `sorted` is not stable.
        return result.enumerated()
            .sorted { lhs, rhs in
                let lSolved = solved.isSolved(lhs.element.id)
                let rSolved = solved.isSolved(rhs.element.id)
                if lSolved != rSolved { return !lSolved }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Distinct topics across the company's problems, most common first, tallied
    /// once when the list loads rather than on every render.
    private static func topics(in problems: [DSAProblem]) -> [TopicCount] {
        var counts: [String: Int] = [:]
        for problem in problems {
            for topic in problem.topics { counts[topic, default: 0] += 1 }
        }
        return counts
            .map { TopicCount(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
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

/// A topic name paired with how many of the company's problems carry it.
struct TopicCount: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}

// MARK: - Topic filter sheet

/// The opt-in topic chooser. Multi-select, union semantics; the count beside
/// each topic tells the user how much a filter will narrow the list.
private struct TopicFilterSheet: View {

    let topics: [TopicCount]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            if topics.isEmpty {
                Text("No topic tags for this company")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: PPSpacing.sm) {
                        ForEach(topics) { topic in
                            row(topic)
                        }
                    }
                    .padding(PPSpacing.xl)
                }
                .scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: PPSpacing.md) {
            Text("Filter by topic").font(.ppTitle)
            Spacer()
            if !selection.isEmpty {
                Button("Clear") { withAnimation(PPMotion.snappy) { selection = [] } }
                    .font(.ppBodyMedium)
                    .foregroundStyle(Color.ppMuted)
            }
            Button("Done") { dismiss() }
                .font(.ppBodyMedium)
                .foregroundStyle(Color.ppAccent400)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.xl)
        .padding(.bottom, PPSpacing.md)
    }

    private func row(_ topic: TopicCount) -> some View {
        let isSelected = selection.contains(topic.name)

        return Button {
            withAnimation(PPMotion.snappy) {
                if isSelected { selection.remove(topic.name) } else { selection.insert(topic.name) }
            }
        } label: {
            HStack(spacing: PPSpacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.ppAccent : Color.ppMuted)
                Text(topic.name)
                    .font(.ppBodyMedium)
                Spacer(minLength: PPSpacing.sm)
                Text("\(topic.count)")
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
            }
            .padding(.horizontal, PPSpacing.lg)
            .frame(height: PPSize.control)
            .background(
                isSelected ? Color.ppElevated : Color.ppSurface,
                in: .rect(cornerRadius: PPRadius.md)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.md)
                    .strokeBorder(isSelected ? Color.ppAccent.opacity(0.5) : Color.ppBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scrollable list with a wide, grabbable scrollbar

/// Live scroll position, shared with the scrollbar. An object (not view `@State`)
/// so that updating it on every scroll frame re-renders only the thin scrollbar,
/// never the list — the parent's filter/sort over thousands of rows stays put.
@Observable
private final class ScrollTracker {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0

    var maxOffset: CGFloat { max(contentHeight - viewportHeight, 0) }
    var isScrollable: Bool { maxOffset > 1 }
    var progress: Double { maxOffset > 0 ? min(max(Double(offset / maxOffset), 0), 1) : 0 }
    /// Fraction of the content on screen — sizes the thumb.
    var visibleRatio: Double { contentHeight > 0 ? min(max(Double(viewportHeight / contentHeight), 0), 1) : 1 }
}

/// The problem list paired with a custom scrollbar. Splits scroll tracking into
/// `ScrollTracker` so the heavy `LazyVStack` isn't rebuilt as the thumb moves.
private struct ProblemListScroll<Row: View>: View {

    let problems: [DSAProblem]
    @ViewBuilder let row: (DSAProblem) -> Row

    @State private var tracker = ScrollTracker()
    private let space = "lcProblems"

    var body: some View {
        // Outer reader gives the viewport height directly; the inner one tracks
        // how far the content has scrolled. Both write straight to `tracker`,
        // which only the scrollbar observes.
        GeometryReader { outer in
            ScrollViewReader { proxy in
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: PPSpacing.md) {
                            ForEach(problems) { problem in
                                row(problem).id(problem.id)
                            }
                        }
                        .padding(.leading, PPSpacing.xl)
                        .padding(.bottom, PPSpacing.xl)
                        .background(
                            GeometryReader { inner in
                                let frame = inner.frame(in: .named(space))
                                Color.clear
                                    .onAppear {
                                        tracker.offset = -frame.minY
                                        tracker.contentHeight = frame.height
                                    }
                                    .onChange(of: frame) { _, new in
                                        tracker.offset = -new.minY
                                        tracker.contentHeight = new.height
                                    }
                            }
                        )
                    }
                    .coordinateSpace(name: space)
                    .scrollIndicators(.hidden)

                    ProblemScrollbar(tracker: tracker, problems: problems, proxy: proxy)
                }
                .onAppear { tracker.viewportHeight = outer.size.height }
                .onChange(of: outer.size.height) { _, height in tracker.viewportHeight = height }
            }
        }
    }
}

/// A slim thumb inside a wide (24pt) hit column. Reflects the scroll position
/// and can be dragged — or clicked anywhere on the track — to scrub the list.
private struct ProblemScrollbar: View {

    let tracker: ScrollTracker
    let problems: [DSAProblem]
    let proxy: ScrollViewProxy

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    var body: some View {
        GeometryReader { geo in
            let trackHeight = geo.size.height
            let thumbHeight = min(trackHeight, max(52, trackHeight * CGFloat(tracker.visibleRatio)))
            let travel = max(trackHeight - thumbHeight, 1)
            let thumbY = CGFloat(isDragging ? dragProgress : tracker.progress) * travel

            ZStack(alignment: .top) {
                // A clear fill makes the whole column a hit target.
                Color.clear

                // Full-height track, so the control is discoverable at rest.
                Capsule()
                    .fill(Color.ppBorder)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)

                Capsule()
                    .fill(isDragging ? Color.ppAccent : Color.ppMuted)
                    .frame(width: isDragging ? 8 : 6, height: thumbHeight)
                    .offset(y: thumbY)
            }
            .frame(width: geo.size.width, height: trackHeight)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let p = min(max(Double((value.location.y - thumbHeight / 2) / travel), 0), 1)
                        dragProgress = p
                        let index = Int((p * Double(max(problems.count - 1, 0))).rounded())
                        if problems.indices.contains(index) {
                            proxy.scrollTo(problems[index].id, anchor: .top)
                        }
                    }
                    .onEnded { _ in isDragging = false }
            )
            .opacity(tracker.isScrollable ? 1 : 0)
            .animation(PPMotion.snappy, value: isDragging)
            .accessibilityHidden(true)
        }
        .frame(width: 32)
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
