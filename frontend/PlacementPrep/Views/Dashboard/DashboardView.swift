import SwiftUI

/// The app's four destinations.
enum AppTab: Hashable {
    case home, quiz, interview, companies
}

/// Root TabView. Selection is hoisted into state so Home's shortcut cards can
/// switch tabs — tapping "Mock Interview" on Home should land on the same screen
/// the tab bar reaches, not push a second copy onto Home's stack.
///
/// Uses the system tab bar restyled by `PPAppearance` rather than a custom bar,
/// so safe-area insets, keyboard avoidance and VoiceOver ordering keep working.
struct DashboardView: View {

    @State private var selectedTab: AppTab = .home

    var body: some View {
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

#Preview {
    DashboardView()
        .environment(CompanyBank())
        .environment(SolvedStore.preview())
        .environment(QuizBank())
        .environment(QuizProgressStore.preview())
        .environment(SavedQuestionsStore.preview())
        .environmentObject(AuthViewModel())
}
