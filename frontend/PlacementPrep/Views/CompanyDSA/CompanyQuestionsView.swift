import SwiftUI

struct CompanyQuestionsView: View {

    let company: DSACompany

    @Environment(CompanyBank.self) private var bank
    @Environment(SolvedStore.self) private var solved
    @Environment(StreakStore.self) private var streak
    @Environment(XPStore.self) private var xp

    @State private var problems: [DSAProblem] = []
    @State private var availableTopics: [TopicCount] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var difficultyFilter: DifficultyFilter = .all
    @State private var topicFilter: Set<String> = []
    @State private var showTopicSheet = false

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
        .ppContentColumn(PPSize.wideColumn)
    }

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

    private var rows: some View {
        ProblemListScroll(problems: visible) { problem in
            row(problem)
        }
    }

    private func row(_ problem: DSAProblem) -> some View {
        let isSolved = solved.isSolved(problem.id)

        return PPCard(wash: problem.difficulty.accent.opacity(isSolved ? 0.25 : 1)) {
            HStack(spacing: PPSpacing.md) {
                PPCheckbox(
                    isOn: Binding(
                        get: { isSolved },
                        set: { _ in
                            withAnimation(PPMotion.settle) { solved.toggle(problem.id) }
                            if isSolved {
                                PPHaptics.light()
                            } else {
                                PPHaptics.success()
                                streak.recordActivity()
                                xp.awardStreakDay()
                                xp.award(.problemSolved(
                                    slug: problem.id,
                                    difficulty: problem.difficulty
                                ))
                            }
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

    private var visible: [DSAProblem] {
        var result = problems

        if let level = difficultyFilter.difficulty {
            result = result.filter { $0.difficulty == level }
        }

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

        return result.enumerated()
            .sorted { lhs, rhs in
                let lSolved = solved.isSolved(lhs.element.id)
                let rSolved = solved.isSolved(rhs.element.id)
                if lSolved != rSolved { return !lSolved }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

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
    var accent: Color {
        switch self {
        case .easy: .ppEasy
        case .medium: .ppMedium
        case .hard: .ppHard
        }
    }
}

struct TopicCount: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}

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

@Observable
private final class ScrollTracker {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0

    var maxOffset: CGFloat { max(contentHeight - viewportHeight, 0) }
    var isScrollable: Bool { maxOffset > 1 }
    var progress: Double { maxOffset > 0 ? min(max(Double(offset / maxOffset), 0), 1) : 0 }
    var visibleRatio: Double { contentHeight > 0 ? min(max(Double(viewportHeight / contentHeight), 0), 1) : 1 }
}

private struct ProblemListScroll<Row: View>: View {

    let problems: [DSAProblem]
    @ViewBuilder let row: (DSAProblem) -> Row

    @State private var tracker = ScrollTracker()
    private let space = "lcProblems"

    var body: some View {
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
                Color.clear

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
    .environment(StreakStore.preview())
    .environment(XPStore.preview())
}
