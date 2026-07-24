import SwiftUI

/// Shown for the brief moment on launch while a stored token is validated
/// against the backend. Keeps the app from flashing the dashboard before we
/// know whether the saved session is still good.
struct LaunchSplashView: View {
    var body: some View {
        VStack(spacing: PPSpacing.lg) {
            Text("PlacementPrep")
                .font(.ppDisplay)
                .foregroundStyle(Color.ppText)
            ProgressView()
                .tint(Color.ppAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ppScreenBackground()
    }
}

#Preview {
    LaunchSplashView()
}
