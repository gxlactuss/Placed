import SwiftUI

/// Home tab. Assembled entirely from the `DesignSystem` primitives. Name and
/// role come from the signed-in account, the streak from `StreakStore`, and the
/// practice counts are read live from the bundled content — so nothing on this
/// screen can drift from reality.
struct HomeView: View {

    @Binding var selectedTab: AppTab

    @Environment(QuizBank.self) private var quizBank
    @Environment(CompanyBank.self) private var companyBank
    @Environment(StreakStore.self) private var streak
    @Environment(XPStore.self) private var xp
    @EnvironmentObject private var auth: AuthViewModel

    @State private var showThemeSheet = false
    @State private var showSavedSheet = false
    @State private var showIconSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                topBar
                greeting
                    .padding(.bottom, PPSpacing.xs)
                interviewHero
                keepPracticing
                xpCard
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
        .sheet(isPresented: $showSavedSheet) { SavedQuestionsView() }
        .sheet(isPresented: $showIconSheet) { AppIconPickerView() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            Text(todayLine)
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
            Spacer(minLength: PPSpacing.md)
            FocusModeToggle()
                .padding(.trailing, PPSpacing.sm)
            // Tapping the avatar opens the profile menu. It holds just the theme
            // switcher today; account/settings items land here later.
            Menu {
                Button {
                    showSavedSheet = true
                } label: {
                    Label("Saved questions", systemImage: "bookmark")
                }
                Button {
                    showThemeSheet = true
                } label: {
                    Label("Themes", systemImage: "paintpalette")
                }
                Button {
                    showIconSheet = true
                } label: {
                    Label("App icon", systemImage: "app.badge")
                }
                Divider()
                Button(role: .destructive) {
                    auth.logout()
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                PPAvatar(initials: initials(from: displayName))
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
                + Text(displayRole)
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

    // MARK: - XP

    /// The balance, the tier it sits in, and how far it is to the next one.
    /// Tapping opens the icon gallery — the tiers are only meaningful because of
    /// what they unlock, so the card is the way in.
    private var xpCard: some View {
        Button {
            showIconSheet = true
        } label: {
            PPCard {
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        (
                            Text("\(xp.total)")
                                .font(.ppStat())
                                .foregroundStyle(Color.ppAccent)
                            + Text(" XP")
                                .font(.ppHeadline)
                                .foregroundStyle(Color.ppText)
                        )
                        .contentTransition(.numericText())

                        Spacer(minLength: PPSpacing.md)

                        PPBadge(xp.level.title, tone: .accent)
                    }

                    PPProgressBar(progress: xp.progressInLevel)

                    HStack(spacing: PPSpacing.sm) {
                        Text(xpFootnote)
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                        Spacer(minLength: PPSpacing.sm)
                        Label("Icons", systemImage: "app.badge")
                            .font(.ppMicro)
                            .foregroundStyle(Color.ppAccent400)
                    }
                }
            }
        }
        .buttonStyle(.ppPressable)
        .animation(PPMotion.settle, value: xp.total)
    }

    private var xpFootnote: String {
        guard let next = xp.nextLevel, let remaining = xp.xpToNextLevel else {
            return "Top tier — every icon unlocked"
        }
        return "\(remaining) XP to \(next.title)"
    }

    // MARK: - Streak

    private var streakCard: some View {
        PPCard {
            HStack(spacing: PPSpacing.lg) {
                PPIconTile(systemName: "moon.fill", tint: .ppAccent400)

                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    (
                        Text("\(streak.currentStreak)")
                            .font(.ppStat())
                            .foregroundStyle(Color.ppAccent)
                        + Text(" day streak")
                            .font(.ppHeadline)
                            .foregroundStyle(Color.ppText)
                    )
                    Text(streakSubtitle)
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: PPSpacing.md)

                streakDots
            }
        }
    }

    /// Nudges toward the next thing rather than restating the number above:
    /// nothing yet → how to start, kept it today → the best to beat, and an
    /// untouched day on a live streak → the one that matters.
    private var streakSubtitle: String {
        let best = streak.bestStreak
        if streak.currentStreak == 0 {
            return "A quiz, a solved problem or a mock round starts it."
        }
        if !streak.didPracticeToday {
            return "Practise today to keep it alive"
        }
        return streak.currentStreak >= best
            ? "Your best run yet · keep going"
            : "Best: \(best) days"
    }

    /// Compact week dots: filled for practised days, a ring for today, a faint
    /// disc for the rest of the week.
    private var streakDots: some View {
        let progress = streak.weekProgress
        let todayIndex = streak.todayIndexInWeek
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
        .accessibilityLabel("\(progress.count { $0 }) of 7 days this week")
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

    /// Real signed-in name when the account carries one, else the sample name
    /// (a token restored from the Keychain has no user attached until a `/me`
    /// endpoint exists, so the fallback keeps the header populated).
    private var displayName: String {
        let name = auth.currentUser?.fullName?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? SampleData.userName : name
    }

    private var displayRole: String {
        let role = auth.currentUser?.targetRole?.trimmingCharacters(in: .whitespaces) ?? ""
        return role.isEmpty ? SampleData.targetRole : role
    }

    private var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
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
        .environment(StreakStore.preview(daysBack: 5))
        .environment(XPStore.preview(total: 120))
        .environment(FocusModeStore.preview())
        .environmentObject(AuthViewModel())
}
