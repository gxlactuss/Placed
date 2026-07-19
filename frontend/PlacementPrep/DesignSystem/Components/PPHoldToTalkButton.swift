import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Push-to-talk microphone control for the mock interview screen.
///
/// Recording runs for exactly as long as the finger is down. The gesture uses a
/// zero-distance `DragGesture` rather than `onLongPressGesture` so recording
/// starts on touch-down with no hold delay, and — importantly — still ends if
/// the finger slides off the button before lifting.
struct PPHoldToTalkButton: View {

    /// Normalised input level, 0...1. Drives the halo so the user can see they
    /// are being heard. Feed it from the recogniser; a constant is fine until then.
    var level: Double = 0
    var diameter: CGFloat = 76
    var isRecording: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    @GestureState private var isPressed = false

    private var clampedLevel: Double { min(max(level, 0), 1) }

    var body: some View {
        Circle()
            .fill(Color.ppHard)
            .frame(width: diameter, height: diameter)
            .overlay {
                Image(systemName: "mic.fill")
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(
                color: Color.ppHard.opacity(isRecording ? 0.45 + 0.35 * clampedLevel : 0),
                radius: isRecording ? 16 + 26 * clampedLevel : 0
            )
            .scaleEffect(isRecording ? 1.0 + 0.06 * clampedLevel : 1)
            .animation(.easeOut(duration: 0.12), value: clampedLevel)
            .animation(.easeOut(duration: 0.18), value: isRecording)
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        // Fires continuously while held; the transition itself is
                        // handled in onChange so start/stop stay balanced.
                        state = true
                    }
            )
            .onChange(of: isPressed) { _, pressed in
                if pressed {
                    impact(strong: true)
                    onStart()
                } else {
                    impact(strong: false)
                    onStop()
                }
            }
            .accessibilityLabel(Text("Hold to talk"))
            .accessibilityHint(Text("Touch and hold to record your answer, release to send"))
            .accessibilityAddTraits(.startsMediaSession)
            // Hold gestures are hard to perform with some motor impairments, so
            // VoiceOver users get a plain toggle instead of the press-and-hold.
            .accessibilityAction {
                isRecording ? onStop() : onStart()
            }
    }

    /// The parameter is a plain Bool rather than a `UIImpactFeedbackStyle` so the
    /// signature itself stays free of UIKit types on platforms without it.
    private func impact(strong: Bool) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: strong ? .medium : .light).impactOccurred()
        #endif
    }
}

#Preview("Hold to talk") {
    @Previewable @State var recording = false
    @Previewable @State var level = 0.0

    VStack(spacing: PPSpacing.xl) {
        Text(recording ? "Listening… release when you're done" : "Hold the mic to answer")
            .font(.ppCaption)
            .foregroundStyle(Color.ppMuted)

        PPHoldToTalkButton(level: level, isRecording: recording) {
            recording = true
            level = 0.6
        } onStop: {
            recording = false
            level = 0
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ppScreenBackground()
}
