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
    @State private var resumeReviews = ResumeReviewStore()
    @State private var connectivity = ConnectivityMonitor()
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
                            .environment(resumeReviews)
                            .environment(companyBank)
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
                            .environment(resumeReviews)
                            .task(id: auth.currentUser?.id) {
                                guard let id = auth.currentUser?.id else { return }
                                savedQuestions.adopt(userId: id)
                                streak.adopt(userId: id)
                                xp.adopt(userId: id)
                                interviewSetup.adopt(userId: id)
                                resumeReviews.adopt(userId: id)
                                quizBank.adopt(role: CareerRole(title: auth.currentUser?.targetRole))
                                await quizProgress.sync(userId: id)
                                await solvedStore.sync(userId: id)
                            }
                            .onChange(of: auth.currentUser?.targetRole) { _, role in
                                quizBank.adopt(role: CareerRole(title: role))
                            }
                            .onChange(of: connectivity.isOnline) { _, online in
                                // Progress sync fails offline; catch up once the network is back.
                                guard online, let id = auth.currentUser?.id else { return }
                                Task {
                                    await quizProgress.sync(userId: id)
                                    await solvedStore.sync(userId: id)
                                }
                            }
                    }
                case .unauthenticated:
                    AuthView()
                }
            }
            .environment(connectivity)
            .ppOfflineBanner(isOffline: !connectivity.isOnline)
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
                    resumeReviews.clear()
                }
            }
            .onAppear {
                // Account deletion erases what the per-user stores persisted.
                // Device preferences (theme, app icon, focus mode) are kept.
                auth.onAccountDeleted = { [quizProgress, solvedStore, savedQuestions, streak, xp, interviewSetup, resumeReviews] in
                    quizProgress.eraseAccountData()
                    solvedStore.eraseAccountData()
                    savedQuestions.eraseAccountData()
                    streak.eraseAccountData()
                    xp.eraseAccountData()
                    interviewSetup.eraseAccountData()
                    resumeReviews.eraseAccountData()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { theme.refresh() }
        }
    }
}
