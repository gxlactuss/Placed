import SwiftUI

@main
struct PlacementPrepApp: App {

    init() {
        PPAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            // Auth is not wired up yet — the app opens straight into the tabs.
            // Reinstate the AuthViewModel gate here when login returns.
            DashboardView()
                // Dark-only for now; remove once the themes feature lands.
                .preferredColorScheme(.dark)
        }
    }
}
