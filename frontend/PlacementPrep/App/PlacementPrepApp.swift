import SwiftUI

@main
struct PlacementPrepApp: App {

    /// Owned here so solved state and the parsed-CSV cache survive tab switches.
    @State private var companyBank = CompanyBank()
    @State private var solvedStore = SolvedStore()
    @State private var quizBank = QuizBank()
    @State private var quizProgress = QuizProgressStore()

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
                // Dark-only for now; remove once the themes feature lands.
                .preferredColorScheme(.dark)
        }
    }
}
