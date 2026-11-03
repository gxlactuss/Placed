import SwiftUI

struct LaunchSplashView: View {
    var body: some View {
        VStack(spacing: PPSpacing.lg) {
            Text("Placed")
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
