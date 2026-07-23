import SwiftUI

/// Home tab. Assembled entirely from the `DesignSystem` primitives. Profile
/// copy (name, role, streak) still comes from `SampleData`; the practice counts
/// are read live from the bundled content so they can never drift from reality.
struct HomeView: View {

    @Binding var selectedTab: AppTab

    @Environment(QuizBank.self) private var quizBank
    @Environment(CompanyBank.self) private var companyBank

    @State private var showThemeSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                topBar
                greeting
                    .padding(.bottom, PPSpacing.xs)
                interviewHero
                keepPracticing
                streakCard
            }
            .padding(PPSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        // Building the deduped catalog is the only way to show a true problem
        // count; it runs once, off the main actor, and flips the card when ready.
        .task { await companyBank.loadCatalogIfNeeded() }
        .sheet(isPresented: $showThemeSheet) { ThemePickerView() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            Text(todayLine)
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
            Spacer()
            // Tapping the avatar opens the profile menu. It holds just the theme
            // switcher today; account/settings items land here later.
            Menu {
                Button {
                    showThemeSheet = true
                } label: {
                    Label("Themes", systemImage: "paintpalette")
                }
            } label: {
                PPAvatar(initials: initials(from: SampleData.userName))
            }
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text("\(timeOfDayGreeting),")
                .font(.ppBody)
                .foregroundStyle(Color.ppMuted)

            Text("\(firstName).")
                .font(.ppDisplay)

            (
                Text("Ready when you are. Let's train for ")
                    .foregroundStyle(Color.ppMuted)
                + Text(SampleData.targetRole)
                    .foregroundStyle(Color.ppAccent400)
                + Text(".")
                    .foregroundStyle(Color.ppMuted)
            )
            .font(.ppBody)
            .padding(.top, PPSpacing.xs)
        }
    }

    // MARK: - Interview hero

    /// The one loud moment on the screen. Warm amber-wash panel with a large
    /// mic watermark and an amber call to action — flat, no gradient or glow.
    private var interviewHero: some View {
        Button {
            selectedTab = .interview
        } label: {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                Text("AI Mock Interview")
                    .font(.ppSectionLabel)
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(Color.ppAccent400)

                Text("Practice\nthe real thing.")
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Voice round · live feedback · ~15 min")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)

                startRoundPill
                    .padding(.top, PPSpacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PPSpacing.xl)
            .background(alignment: .trailing) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 210, weight: .regular))
                    .foregroundStyle(Color.ppAccent.opacity(0.12))
                    .offset(x: 55)
                    .accessibilityHidden(true)
            }
            .background(Color.ppAccentSection)
            .clipShape(.rect(cornerRadius: PPRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.lg)
                    .strokeBorder(Color.ppAccent700.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.ppPressable)
    }

    /// Looks like a `ppPrimary` button but is a plain label, so it can live
    /// inside the tappable hero card without nesting a second button.
    private var startRoundPill: some View {
        HStack(spacing: PPSpacing.sm) {
            Text("Start round")
            Image(systemName: "arrow.right")
        }
        .font(.ppBodyMedium)
        .foregroundStyle(Color.ppOnAccent)
        .padding(.horizontal, PPSpacing.xl)
        .frame(height: 46)
        .background(Color.ppAccent, in: .capsule)
    }

    // MARK: - Keep practicing

    private var keepPracticing: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPSectionHeader("Keep practicing")

            HStack(spacing: PPSpacing.md) {
                practiceCard(
                    icon: "checklist",
                    title: "Quiz",
                    subtitle: "CS · DSA · Aptitude",
                    metric: "\(quizQuestionCount.formatted()) questions",
                    tab: .quiz
                )
                practiceCard(
                    icon: "building.2.fill",
                    title: "LeetCode",
                    subtitle: "Company-wise DSA",
                    metric: problemMetric,
                    tab: .companies
                )
            }
        }
    }

    private func practiceCard(
        icon: String,
        title: String,
        subtitle: String,
        metric: String,
        tab: AppTab
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            PPCard {
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    PPIconTile(systemName: icon, tint: .ppAccent400)

                    VStack(alignment: .leading, spacing: PPSpacing.xs) {
                        Text(title)
                            .font(.ppHeadline)
                        Text(subtitle)
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                    }

                    Spacer(minLength: PPSpacing.md)

                    Text(metric)
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppAccent400)
                }
                .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            }
        }
        .buttonStyle(.ppPressable)
    }

    // MARK: - Streak

    private var streakCard: some View {
        PPCard {
            HStack(spacing: PPSpacing.lg) {
                PPIconTile(systemName: "moon.fill", tint: .ppAccent400)

                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    (
                        Text("\(SampleData.streakDays)")
                            .font(.ppStat())
                            .foregroundStyle(Color.ppAccent)
                        + Text(" day streak")
                            .font(.ppHeadline)
                            .foregroundStyle(Color.ppText)
                    )
                    Text("Best: \(SampleData.bestStreakDays) days · you're on fire")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                }

                Spacer(minLength: PPSpacing.md)

                streakDots
            }
        }
    }

    /// Compact week dots: filled for completed days, a ring for today, a faint
    /// disc for days still ahead.
    private var streakDots: some View {
        let progress = SampleData.weekProgress
        let todayIndex = progress.firstIndex(of: false) ?? progress.count - 1
        return HStack(spacing: PPSpacing.sm) {
            ForEach(progress.indices, id: \.self) { index in
                Group {
                    if progress[index] {
                        Circle().fill(Color.ppAccent)
                    } else if index == todayIndex {
                        Circle().strokeBorder(Color.ppAccent, lineWidth: 1.5)
                    } else {
                        Circle().fill(Color.ppElevated)
                    }
                }
                .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(SampleData.weekProgress.filter { $0 }.count) of 7 days this week")
    }

    // MARK: - Live counts

    private var quizQuestionCount: Int {
        quizBank.quizzes.reduce(0) { $0 + $1.questions.count }
    }

    /// Shows the true distinct-problem count once the catalog has been built;
    /// falls back to the company count until then so the card is never blank.
    private var problemMetric: String {
        companyBank.isCatalogReady
            ? "\(companyBank.catalog.count.formatted()) problems"
            : "\(companyBank.companies.count) companies"
    }

    // MARK: - Helpers

    private var todayLine: String {
        Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var firstName: String {
        SampleData.userName.split(separator: " ").first.map(String.init) ?? SampleData.userName
    }

    private func initials(from name: String) -> String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }
}

#Preview {
    @Previewable @State var tab: AppTab = .home
    HomeView(selectedTab: $tab)
        .environment(QuizBank())
        .environment(CompanyBank())
        .environment(SolvedStore.preview())
}
