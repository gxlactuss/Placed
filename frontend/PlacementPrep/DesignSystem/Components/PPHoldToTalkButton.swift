import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PPHoldToTalkButton: View {
    var level: Double = 0
    var diameter: CGFloat = 76
    var isRecording: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    var onCancel: (() -> Void)? = nil

    @GestureState private var isPressed = false
    @GestureState private var dragX: CGFloat = 0
    @State private var didCancel = false
    @State private var discards = 0
    @State private var isShowingDiscard = false

    private var clampedLevel: Double { min(max(level, 0), 1) }

    private var cancelDistance: CGFloat { diameter * 1.15 }
    private var binSize: CGFloat { diameter * 0.5 }
    private var binOffset: CGFloat {
        -(cancelDistance + diameter / 2 + PPSpacing.sm + binSize / 2)
    }
    private var chevronOffset: CGFloat {
        -(diameter / 2 + (cancelDistance + PPSpacing.sm) / 2)
    }

    private var slideProgress: Double {
        guard onCancel != nil, isPressed, isRecording, !didCancel else { return 0 }
        return min(max(-dragX / cancelDistance, 0), 1)
    }

    private var isSliding: Bool { isPressed && isRecording && !didCancel }

    var body: some View {
        ZStack {
            if onCancel != nil { slideTrack }
            mic
        }
    }

    private var mic: some View {
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
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .updating($dragX) { value, state, _ in
                        state = value.translation.width
                    }
            )
            .offset(x: -cancelDistance * slideProgress)
            .animation(isSliding ? nil : PPMotion.snappy, value: slideProgress)
            .onChange(of: isPressed) { _, pressed in
                if pressed {
                    didCancel = false
                    impact(.press)
                    onStart()
                } else if didCancel {
                    didCancel = false
                } else {
                    impact(.release)
                    onStop()
                }
            }
            .onChange(of: dragX) { _, x in
                guard let onCancel, isSliding, -x >= cancelDistance else { return }
                didCancel = true
                discards += 1
                impact(.discard)
                isShowingDiscard = true
                onCancel()
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    isShowingDiscard = false
                }
            }
            .accessibilityLabel(Text("Hold to talk"))
            .accessibilityHint(Text(onCancel == nil
                ? "Touch and hold to record your answer, release to send"
                : "Touch and hold to record your answer, release to send, or slide left to discard it"))
            .accessibilityAddTraits(.startsMediaSession)
            .accessibilityAction {
                isRecording ? onStop() : onStart()
            }
            .accessibilityActions {
                if isRecording, let onCancel {
                    Button("Discard recording") { onCancel() }
                }
            }
    }

    private var slideTrack: some View {
        let visible = isSliding || isShowingDiscard
        return ZStack {
            bin
                .offset(x: binOffset)

            Image(systemName: "chevron.left.2")
                .font(.ppCaption.weight(.semibold))
                .foregroundStyle(Color.ppMuted)
                .opacity(isShowingDiscard ? 0 : max(0, 1 - slideProgress * 2))
                .offset(x: chevronOffset)
        }
        .opacity(visible ? 1 : 0)
        .animation(PPMotion.snappy, value: visible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var bin: some View {
        let hot = isShowingDiscard || slideProgress >= 1
        return Image(systemName: isShowingDiscard ? "trash.fill" : "trash")
            .font(.system(size: binSize * 0.46, weight: .semibold))
            .foregroundStyle(hot ? Color.ppHard : Color.ppMuted)
            .symbolEffect(.bounce, value: discards)
            .frame(width: binSize, height: binSize)
            .background(Color.ppSurface, in: .circle)
            .overlay { Circle().strokeBorder(Color.ppBorder, lineWidth: 1) }
            .overlay {
                Circle().strokeBorder(
                    Color.ppHard.opacity(isShowingDiscard ? 1 : slideProgress),
                    lineWidth: 1
                )
            }
            .scaleEffect(1 + 0.18 * (isShowingDiscard ? 1 : slideProgress))
    }

    private enum Feel { case press, release, discard }

    private func impact(_ feel: Feel) {
        #if canImport(UIKit)
        switch feel {
        case .press: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .release: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .discard: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }
}

#Preview("Hold to talk") {
    @Previewable @State var recording = false
    @Previewable @State var level = 0.0
    @Previewable @State var status = "Hold the mic to answer"

    VStack(spacing: PPSpacing.xl) {
        PPHoldToTalkButton(level: level, isRecording: recording) {
            recording = true
            level = 0.6
            status = "Release to send · slide left to discard"
        } onStop: {
            recording = false
            level = 0
            status = "Sent"
        } onCancel: {
            recording = false
            level = 0
            status = "Discarded"
        }

        Text(status)
            .font(.ppCaption)
            .foregroundStyle(Color.ppMuted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ppScreenBackground()
}
