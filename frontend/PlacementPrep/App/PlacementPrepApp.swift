import SwiftUI

@main
struct PlacementPrepApp: App {

    /// Owned here so solved state and the parsed-CSV cache survive tab switches.
    @State private var companyBank = CompanyBank()
    @State private var solvedStore = SolvedStore()
    @State private var quizBank = QuizBank()
    @State private var quizProgress = QuizProgressStore()
    @State private var savedQuestions = SavedQuestionsStore()
    /// The JWT gate. When a token is in the Keychain the app opens straight to
    /// the tabs; otherwise `AuthView` is shown until sign-in succeeds.
    @StateObject private var auth = AuthViewModel()
    /// The active theme drives every `Color.pp*` token; reading it here also
    /// keeps the scene's colour scheme in step with the chosen theme.
    @Bindable private var theme = ThemeStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PPAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    DashboardView()
                        .environment(companyBank)
                        .environment(solvedStore)
                        .environment(quizBank)
                        .environment(quizProgress)
                        .environment(savedQuestions)
                } else {
                    AuthView()
                }
            }
            .environmentObject(auth)
            .animation(PPMotion.settle, value: auth.isAuthenticated)
            .preferredColorScheme(theme.activeTheme.palette.colorScheme)
        }
        // Catch a day/night boundary that passed while the app was suspended.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { theme.refresh() }
        }
    }
}
