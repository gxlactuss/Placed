import SwiftUI

/// Solved-state control on the company problem list.
struct PPCheckbox: View {

    @Binding var isOn: Bool
    var size: CGFloat = PPSize.checkbox

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 7)
                .fill(isOn ? Color.ppAccent : Color.ppSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isOn ? .clear : Color.ppBorderStrong, lineWidth: 1)
                }
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// The circular day marker in the daily streak strip.
struct PPStreakDay: View {

    let label: String
    let isComplete: Bool
    /// Draws the dashed ring used for today when practice is still pending.
    var isToday: Bool = false

    var body: some View {
        VStack(spacing: PPSpacing.sm) {
            ZStack {
                if isComplete {
                    Circle().fill(Color.ppAccent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .strokeBorder(
                            isToday ? Color.ppAccent : Color.ppBorderStrong,
                            style: StrokeStyle(lineWidth: 1.5, dash: isToday ? [3, 3] : [])
                        )
                }
            }
            .frame(width: 32, height: 32)

            Text(label)
                .font(.ppMicro)
                .foregroundStyle(Color.ppMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Selection controls") {
    @Previewable @State var solved = true
    @Previewable @State var unsolved = false

    VStack(spacing: PPSpacing.xxl) {
        HStack(spacing: PPSpacing.lg) {
            PPCheckbox(isOn: $solved)
            PPCheckbox(isOn: $unsolved)
        }

        HStack(spacing: PPSpacing.md) {
            ForEach(Array(["M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                PPStreakDay(label: day, isComplete: true)
            }
            PPStreakDay(label: "S", isComplete: false, isToday: true)
        }
    }
    .padding(PPSpacing.xl)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
