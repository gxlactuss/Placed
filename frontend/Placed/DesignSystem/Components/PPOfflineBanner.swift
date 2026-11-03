import SwiftUI

/// A slim notice pinned to the top of the screen while the device is offline.
struct PPOfflineBanner: View {

    static let message = "You're offline. Quizzes and company lists still work; interviews and resume review need a connection."

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PPSpacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.ppCaption)
                .foregroundStyle(Color.ppAccent400)
            Text(Self.message)
                .font(.ppCaption)
                .foregroundStyle(Color.ppText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PPSpacing.lg)
        .padding(.vertical, PPSpacing.md)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: PPRadius.lg))
        .background(Color.ppElevated.opacity(0.85), in: .rect(cornerRadius: PPRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: PPRadius.lg)
                .strokeBorder(Color.ppBorderStrong, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, PPSpacing.lg)
        .padding(.top, PPSpacing.xs)
        .ppContentColumn()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.message)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct PPOfflineBannerModifier: ViewModifier {

    let isOffline: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isOffline {
                    PPOfflineBanner()
                        // Purely informational: taps pass through to the content underneath.
                        .allowsHitTesting(false)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : PPMotion.settle, value: isOffline)
            .onChange(of: isOffline) { _, offline in
                AccessibilityNotification.Announcement(
                    offline ? PPOfflineBanner.message : "You're back online."
                ).post()
            }
    }
}

extension View {
    /// Shows `PPOfflineBanner` over the top of this view while `isOffline` is true.
    func ppOfflineBanner(isOffline: Bool) -> some View {
        modifier(PPOfflineBannerModifier(isOffline: isOffline))
    }
}

#Preview("Offline banner") {
    ScrollView {
        VStack(alignment: .leading, spacing: PPSpacing.lg) {
            Text("Pick a round").font(.ppDisplay)
            Text("Content under the banner stays tappable.")
                .font(.ppBody)
                .foregroundStyle(Color.ppMuted)
        }
        .padding(PPSpacing.xl)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .foregroundStyle(Color.ppText)
    .ppScreenBackground()
    .ppOfflineBanner(isOffline: true)
}
