import SwiftUI

/// Root TabView housing the three core modules: Quiz, Mock Interview, and
/// Company-wise DSA prep. Presented once AuthViewModel.isAuthenticated is true.
struct DashboardView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        TabView {
            QuizListView()
                .tabItem {
                    Label("Quiz", systemImage: "checklist")
                }

            MockInterviewView()
                .tabItem {
                    Label("Mock Interview", systemImage: "mic.fill")
                }

            CompanyListView()
                .tabItem {
                    Label("Companies", systemImage: "building.2.fill")
                }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthViewModel())
}
