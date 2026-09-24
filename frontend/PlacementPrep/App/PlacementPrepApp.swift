import SwiftUI

@main
struct PlacementPrepApp: App {
    @State private var companyBank = CompanyBank()
    @State private var solvedStore = SolvedStore()
    @State private var quizBank = QuizBank()
    @State private var quizProgress = QuizProgressStore()
    @State private var savedQuestions = SavedQuestionsStore()
    @State private var streak = StreakStore()
    @State private var xp = XPStore()
    @State private var focusMode = FocusModeStore()
    @State private var interviewSetup = InterviewSetupStore()
    @StateObject private var auth = AuthViewModel()
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
                    if let user = auth.currentUser, !user.isVerified {
                        VerifyEmailView()
                    } else if let user = auth.currentUser, !user.onboarded {
                        OnboardingView()
                            .environment(interviewSetup)
                    } else {
                        DashboardView()
                            .environment(companyBank)
                            .environment(solvedStore)
                            .environment(quizBank)
                            .environment(quizProgress)
                            .environment(savedQuestions)
                            .environment(streak)
                            .environment(xp)
                            .environment(focusMode)
                            .environment(interviewSetup)
                            .task(id: auth.currentUser?.id) {
                                guard let id = auth.currentUser?.id else { return }
                                savedQuestions.adopt(userId: id)
                                streak.adopt(userId: id)
                                xp.adopt(userId: id)
                                interviewSetup.adopt(userId: id)
                                quizBank.adopt(role: CareerRole(title: auth.currentUser?.targetRole))
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
            .onChange(of: auth.sessionState) { _, state in
                if state == .unauthenticated {
                    quizProgress.clear()
                    solvedStore.clear()
                    savedQuestions.clear()
                    streak.clear()
                    xp.clear()
                    interviewSetup.clear()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { theme.refresh() }
        }
    }
}
