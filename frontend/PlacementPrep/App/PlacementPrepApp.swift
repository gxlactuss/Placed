import SwiftUI

@main
struct PlacementPrepApp: App {

    /// Owned here so solved state and the parsed-CSV cache survive tab switches.
    @State private var companyBank = CompanyBank()
    @State private var solvedStore = SolvedStore()
    @State private var quizBank = QuizBank()
    @State private var quizProgress = QuizProgressStore()
    @State private var savedQuestions = SavedQuestionsStore()
    /// The active theme drives every `Color.pp*` token; reading it here also
    /// keeps the scene's colour scheme in step with the chosen theme.
    @Bindable private var theme = ThemeStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PPAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            // Auth is not wired up yet — the app opens straight into the tabs.
            // Reinstate the AuthViewModel gate here when login returns.
            DashboardView()
                .environment(companyBank)
                .environment(solvedStore)
                .environment(quizBank)
                .environment(quizProgress)
                .environment(savedQuestions)
                .preferredColorScheme(theme.activeTheme.palette.colorScheme)
        }
        // Catch a day/night boundary that passed while the app was suspended.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { theme.refresh() }
        }
    }
}
