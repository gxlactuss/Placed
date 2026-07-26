import SwiftUI

@main
struct PlacementPrepApp: App {

    /// Owned here so solved state and the parsed-CSV cache survive tab switches.
    @State private var companyBank = CompanyBank()
    @State private var solvedStore = SolvedStore()
    @State private var quizBank = QuizBank()
    @State private var quizProgress = QuizProgressStore()
    @State private var savedQuestions = SavedQuestionsStore()
    /// Device-wide, not per-account: it's a property of how you're practising
    /// right now, so it deliberately isn't reset on sign-out.
    @State private var focusMode = FocusModeStore()
    /// Role + resume-derived project summary, gathered before the first interview.
    @State private var interviewSetup = InterviewSetupStore()
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
                switch auth.sessionState {
                case .checking:
                    LaunchSplashView()
                case .authenticated:
                    // Gate order once signed in: verify email → onboard → tabs.
                    // (currentUser is nil only offline — then go straight to tabs.)
                    if let user = auth.currentUser, !user.isVerified {
                        VerifyEmailView()
                    } else if let user = auth.currentUser, !user.onboarded {
                        OnboardingView()
                    } else {
                        DashboardView()
                            .environment(companyBank)
                            .environment(solvedStore)
                            .environment(quizBank)
                            .environment(quizProgress)
                            .environment(savedQuestions)
                            .environment(focusMode)
                            .environment(interviewSetup)
                            // Reconcile per-user progress with the server whenever
                            // the signed-in user becomes known (login/relaunch).
                            .task(id: auth.currentUser?.id) {
                                guard let id = auth.currentUser?.id else { return }
                                savedQuestions.adopt(userId: id)
                                interviewSetup.adopt(userId: id)
                                await quizProgress.sync(userId: id)
                                await solvedStore.sync(userId: id)
                            }
                    }
                case .unauthenticated:
                    AuthView()
                }
            }
            .environmentObject(auth)
            .animation(PPMotion.settle, value: auth.sessionState)
            .preferredColorScheme(theme.activeTheme.palette.colorScheme)
            // Drop cached progress on sign-out so the next account starts clean.
            .onChange(of: auth.sessionState) { _, state in
                if state == .unauthenticated {
                    quizProgress.clear()
                    solvedStore.clear()
                    savedQuestions.clear()
                    interviewSetup.clear()
                }
            }
        }
        // Catch a day/night boundary that passed while the app was suspended.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { theme.refresh() }
        }
    }
}
