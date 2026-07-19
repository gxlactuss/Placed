import SwiftUI

/// Thin capsule progress track — the resume card and the quiz question counter.
struct PPProgressBar: View {

    /// Clamped to 0...1.
    let progress: Double
    var height: CGFloat = 4
    var tint: Color = .ppAccent

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ppElevated)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: clamped)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(clamped * 100)) percent"))
    }
}

/// The scoring ring on the results screen. The centre is a view builder so the
/// caller decides what sits inside it.
struct PPRingProgress<Center: View>: View {

    let progress: Double
    var diameter: CGFloat = 180
    var lineWidth: CGFloat = 16
    var tint: Color = .ppAccent
    @ViewBuilder var center: Center

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ppElevated, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.6), value: clamped)
    }
}

#Preview("Progress") {
    VStack(spacing: PPSpacing.xxl) {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            HStack {
                Text("Question 3 of 15").font(.ppCaption)
                Spacer()
                Text("20%").font(.ppCaption)
            }
            .foregroundStyle(Color.ppMuted)
            PPProgressBar(progress: 0.2)
        }

        PPRingProgress(progress: 0.73) {
            VStack(spacing: PPSpacing.xs) {
                Text("73%").font(.ppStatFixed(44))
                Text("11 / 15 correct")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }
        }
    }
    .foregroundStyle(Color.ppText)
    .padding(PPSpacing.xl)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
