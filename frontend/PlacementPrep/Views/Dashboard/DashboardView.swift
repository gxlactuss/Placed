import SwiftUI

enum AppTab: Hashable {
    case home, quiz, interview, companies
}

struct DashboardView: View {

    @Environment(XPStore.self) private var xp
    @Environment(CompanyBank.self) private var companyBank
    @Environment(SolvedStore.self) private var solved
    @EnvironmentObject private var auth: AuthViewModel
    @State private var selectedTab: AppTab = .home
    @State private var companiesPath: [DSACompany] = []
    @State private var targetProfile: CompanyProfile?
    @State private var milestone: XPAward?

    var body: some View {
        tabs
            .overlay(alignment: .top) { levelUpBanner }
            .overlay(alignment: .top) { milestoneBanner }
            .task(id: auth.currentUser?.targetCompany) {
                guard let company = companyBank.company(named: auth.currentUser?.targetCompany) else {
                    return targetProfile = nil
                }
                targetProfile = await companyBank.profile(for: company)
            }
            .onChange(of: solved.solvedIDs) { before, after in
                awardMilestones(before: before, after: after)
            }
            .task(id: milestone?.ledgerKey) {
                guard milestone != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                withAnimation(PPMotion.settle) { milestone = nil }
            }
            .task(id: xp.pendingLevelUp) {
                guard let level = xp.pendingLevelUp else { return }
                PPHaptics.levelUp()
                await AppIconService.apply(level)
                try? await Task.sleep(for: .seconds(4))
                withAnimation(PPMotion.settle) { xp.pendingLevelUp = nil }
            }
    }

    @ViewBuilder
    private var levelUpBanner: some View {
        if let level = xp.pendingLevelUp {
            XPLevelUpBanner(level: level) {
                withAnimation(PPMotion.settle) { xp.pendingLevelUp = nil }
            }
            .padding(.horizontal, PPSpacing.xl)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(PPMotion.settle, value: xp.pendingLevelUp)
        }
    }

    /// Solving problems that push target-company readiness past 25/50/75/100% pays out once each.
    private func awardMilestones(before: Set<String>, after: Set<String>) {
        guard let profile = targetProfile, let name = profile.companyName else { return }
        let was = CompanyReadiness.compute(profile: profile) { before.contains($0) }.percent
        let now = CompanyReadiness.compute(profile: profile) { after.contains($0) }.percent
        for step in CompanyReadiness.milestones where was < step && now >= step {
            let award = XPAward.readinessMilestone(company: name, percent: step)
            if xp.award(award) > 0 {
                PPHaptics.success()
                withAnimation(PPMotion.settle) { milestone = award }
            }
        }
    }

    @ViewBuilder
    private var milestoneBanner: some View {
        if let milestone, xp.pendingLevelUp == nil {
            HStack(spacing: PPSpacing.md) {
                Image(systemName: "scope")
                    .font(.system(size: 18, weight: .medium))
                VStack(alignment: .leading, spacing: 2) {
                    Text(milestone.reason).font(.ppBodyMedium)
                    Text("+\(milestone.points) XP").font(.ppMicro).opacity(0.8)
                }
                Spacer(minLength: PPSpacing.sm)
            }
            .foregroundStyle(Color.ppOnAccent)
            .padding(.horizontal, PPSpacing.lg)
            .padding(.vertical, PPSpacing.md)
            .background(Color.ppAccent, in: .rect(cornerRadius: PPRadius.lg))
            .padding(.horizontal, PPSpacing.xl)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { withAnimation(PPMotion.settle) { self.milestone = nil } }
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab) { company in
                companiesPath = [company]
                selectedTab = .companies
            }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            QuizCategoryView()
                .tabItem { Label("Quiz", systemImage: "checklist") }
                .tag(AppTab.quiz)

            MockInterviewView()
                .tabItem { Label("Interview", systemImage: "mic.fill") }
                .tag(AppTab.interview)

            CompanyListView(path: $companiesPath)
                .tabItem { Label("LeetCode", systemImage: "building.2.fill") }
                .tag(AppTab.companies)
        }
        .tint(.ppAccent400)
    }
}

private struct XPLevelUpBanner: View {

    let level: XPLevel
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: PPSpacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.ppOnAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(level.title): new tier")
                    .font(.ppBodyMedium)
                Text(level.alternateIconName == nil
                     ? "Keep going."
                     : "A new app icon is yours.")
                    .font(.ppMicro)
                    .opacity(0.8)
            }
            .foregroundStyle(Color.ppOnAccent)

            Spacer(minLength: PPSpacing.sm)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.ppOnAccent)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PPSpacing.lg)
        .padding(.vertical, PPSpacing.md)
        .background(Color.ppAccent, in: .rect(cornerRadius: PPRadius.lg))
    }
}

#Preview {
    DashboardView()
        .environment(CompanyBank())
        .environment(SolvedStore.preview())
        .environment(QuizBank())
        .environment(QuizProgressStore.preview())
        .environment(SavedQuestionsStore.preview())
        .environment(StreakStore.preview(daysBack: 5))
        .environment(XPStore.preview(total: 120))
        .environment(FocusModeStore.preview())
        .environment(InterviewSetupStore.preview())
        .environment(ResumeReviewStore.preview())
        .environmentObject(AuthViewModel())
}
