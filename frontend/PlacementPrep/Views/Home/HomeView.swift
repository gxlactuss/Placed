import SwiftUI

struct HomeView: View {

    @Binding var selectedTab: AppTab
    var onOpenCompany: (DSACompany) -> Void = { _ in }

    @Environment(QuizBank.self) private var quizBank
    @Environment(CompanyBank.self) private var companyBank
    @Environment(SolvedStore.self) private var solved
    @Environment(StreakStore.self) private var streak
    @Environment(XPStore.self) private var xp
    @Environment(ResumeReviewStore.self) private var resumeReviews
    @EnvironmentObject private var auth: AuthViewModel

    @State private var showThemeSheet = false
    @State private var showSavedSheet = false
    @State private var showIconSheet = false
    @State private var showResumeSheet = false
    @State private var showTargetSheet = false
    @State private var targetProfile: CompanyProfile?
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                header
                    .staged(0, appeared)
                InterviewHeroCard {
                    selectedTab = .interview
                }
                .staged(1, appeared)
                tiles
                    .staged(2, appeared)
                keepPracticing
                    .staged(3, appeared)
                targetDetail
                    .staged(4, appeared)
            }
            .padding(.horizontal, PPSpacing.xl)
            .padding(.vertical, PPSpacing.lg)
            .ppContentColumn()
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .onAppear { appeared = true }
        .task { await companyBank.loadCatalogIfNeeded() }
        .task(id: auth.currentUser?.targetCompany) { await loadTargetProfile() }
        .sheet(isPresented: $showThemeSheet) { ThemePickerView() }
        .sheet(isPresented: $showSavedSheet) { SavedQuestionsView() }
        .sheet(isPresented: $showIconSheet) { AppIconPickerView() }
        .sheet(isPresented: $showResumeSheet) { ResumeReviewView() }
        .sheet(isPresented: $showTargetSheet) { TargetCompanySheet() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: PPSpacing.md) {
            Menu {
                Button {
                    showSavedSheet = true
                } label: {
                    Label("Saved questions", systemImage: "bookmark")
                }
                Button {
                    showTargetSheet = true
                } label: {
                    Label("Target company", systemImage: "scope")
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
                PPAvatar(initials: initials(from: displayName), diameter: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(timeOfDayGreeting), \(firstName)")
                    .font(.ppHeadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(displayRole)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppAccent400)
                    .lineLimit(1)
            }

            Spacer(minLength: PPSpacing.sm)

            streakChip
            FocusModeToggle(compact: true)
        }
    }

    private var streakChip: some View {
        let active = streak.didPracticeToday
        return HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .foregroundStyle(active ? Color.ppAccent : Color.ppMuted)
            Text("\(streak.currentStreak)")
                .font(.ppCaption)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, PPSpacing.md)
        .frame(height: 36)
        .background(Color.ppSurface, in: .capsule)
        .overlay { Capsule().strokeBorder(Color.ppBorder, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak.currentStreak) day streak")
    }

    // MARK: - Tiles

    private var tiles: some View {
        Grid(horizontalSpacing: PPSpacing.md, verticalSpacing: PPSpacing.md) {
            GridRow {
                targetTile
                resumeTile
            }
            GridRow {
                xpTile
                streakTile
            }
        }
    }

    private var targetCompany: DSACompany? {
        companyBank.company(named: auth.currentUser?.targetCompany)
    }

    private var targetTile: some View {
        Button {
            if let company = targetCompany {
                onOpenCompany(company)
            } else {
                showTargetSheet = true
            }
        } label: {
            HomeTile(title: targetCompany?.name ?? "Target company") {
                if let company = targetCompany {
                    PPCompanyLogo(companyName: company.name, size: 18)
                } else {
                    HomeTileSymbol(name: "scope")
                }
            } content: {
                if let readiness {
                    HomeTileValue(value: "\(readiness.percent)%", tint: .ppAccent400, unit: "ready")
                    PPProgressBar(progress: readiness.score, height: 5)
                } else if targetCompany != nil {
                    ProgressView().tint(Color.ppMuted)
                } else {
                    Text("Pick a target")
                        .font(.ppHeadline)
                }
            }
        }
        .buttonStyle(.ppPressable)
    }

    private var readiness: CompanyReadiness? {
        guard let targetProfile, targetCompany != nil else { return nil }
        return CompanyReadiness.compute(profile: targetProfile, isSolved: solved.isSolved)
    }

    private var resumeTile: some View {
        Button {
            showResumeSheet = true
        } label: {
            HomeTile(title: "Resume") {
                HomeTileSymbol(name: "doc.text.magnifyingglass")
            } content: {
                if let latest = resumeReviews.latest {
                    let overall = latest.review.overall
                    HomeTileValue(
                        value: "\(overall)",
                        tint: .ppScore(Double(overall) / 10, middle: .ppAccent400),
                        unit: "/100"
                    )
                    PPProgressBar(progress: Double(overall) / 100, height: 5, tint: .ppScore(Double(overall) / 10))
                } else {
                    Text("Get scored")
                        .font(.ppHeadline)
                }
            }
        }
        .buttonStyle(.ppPressable)
    }


    private var xpTile: some View {
        Button {
            showIconSheet = true
        } label: {
            HomeTile(title: xp.level.title) {
                HomeTileSymbol(name: "sparkles")
            } content: {
                HomeTileValue(value: "\(xp.total)", tint: .ppAccent, unit: "XP")
                PPProgressBar(progress: xp.progressInLevel, height: 5)
            }
        }
        .buttonStyle(.ppPressable)
        .animation(PPMotion.settle, value: xp.total)
    }

    private var streakTile: some View {
        HomeTile(title: "Streak") {
            HomeTileSymbol(name: "flame.fill")
        } content: {
            HomeTileValue(value: "\(streak.currentStreak)", unit: streak.currentStreak == 1 ? "day" : "days")
            streakDots
        }
    }


    // MARK: - Practice

    private var keepPracticing: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPSectionHeader("Keep practicing")

            HStack(spacing: PPSpacing.md) {
                practiceRow(icon: "checklist", title: "Quiz", metric: "\(quizQuestionCount.formatted()) questions", tab: .quiz)
                practiceRow(icon: "building.2.fill", title: "LeetCode", metric: problemMetric, tab: .companies)
            }
        }
    }

    private func practiceRow(icon: String, title: String, metric: String, tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            PPCard(padding: PPSpacing.md) {
                HStack(spacing: PPSpacing.sm) {
                    PPIconTile(systemName: icon, size: 32, tint: .ppAccent400)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.ppBodyMedium)
                            .lineLimit(1)
                        Text(metric)
                            .font(.ppMicro)
                            .foregroundStyle(Color.ppMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.ppPressable)
    }

    // MARK: - Target detail

    @ViewBuilder
    private var targetDetail: some View {
        if let company = targetCompany {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                PPSectionHeader("Your target")
                CompanyReadinessCard(
                    company: company,
                    onOpen: onOpenCompany,
                    onPickTarget: { showTargetSheet = true }
                )
            }
        }
    }

    // MARK: - Loading

    private func loadTargetProfile() async {
        guard let company = targetCompany else { return targetProfile = nil }
        targetProfile = await companyBank.profile(for: company)
    }

    // MARK: - Helpers


    private var streakDots: some View {
        let progress = streak.weekProgress
        let todayIndex = streak.todayIndexInWeek
        return HStack(spacing: 5) {
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
                .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(progress.count { $0 }) of 7 days this week")
    }

    private var quizQuestionCount: Int {
        quizBank.quizzes.reduce(0) { $0 + $1.questions.count }
    }

    private var problemMetric: String {
        companyBank.isCatalogReady
            ? "\(companyBank.catalog.count.formatted()) problems"
            : "\(companyBank.companies.count) companies"
    }

    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

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
        .environment(ResumeReviewStore.preview())
        .environmentObject(AuthViewModel())
}

private extension View {
    func staged(_ index: Int, _ appeared: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(PPMotion.settle.delay(Double(index) * 0.06), value: appeared)
    }
}
