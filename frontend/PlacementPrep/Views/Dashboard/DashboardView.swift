import SwiftUI

enum AppTab: Hashable {
    case home, quiz, interview, companies
}

struct DashboardView: View {

    @Environment(XPStore.self) private var xp
    @State private var selectedTab: AppTab = .home

    var body: some View {
        tabs
            .overlay(alignment: .top) { levelUpBanner }
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

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            QuizCategoryView()
                .tabItem { Label("Quiz", systemImage: "checklist") }
                .tag(AppTab.quiz)

            MockInterviewView()
                .tabItem { Label("Interview", systemImage: "mic.fill") }
                .tag(AppTab.interview)

            CompanyListView()
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
        .environmentObject(AuthViewModel())
}
