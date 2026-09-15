import SwiftUI

struct PPVoiceWave: View {

    enum Mode: Equatable {
        case idle
        case listening
        case thinking
    }

    var level: Double = 0
    var mode: Mode = .idle
    var height: CGFloat = 26

    private let sampleCount = 96

    @State private var smoothed: Double = 0

    private var isAnimating: Bool { mode != .idle }

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(
                            in: context,
                            size: size,
                            phase: timeline.date.timeIntervalSinceReferenceDate
                        )
                    }
                }
            } else {
                Canvas { context, size in
                    draw(in: context, size: size, phase: 0)
                }
            }
        }
        .frame(height: height)
        .animation(PPMotion.settle, value: mode)
        .onAppear { smoothed = min(max(level, 0), 1) }
        .onChange(of: level) { _, new in
            withAnimation(.easeOut(duration: 0.09)) {
                smoothed = smoothed * 0.6 + min(max(new, 0), 1) * 0.4
            }
        }
        .onChange(of: mode) { _, new in
            if new != .listening { withAnimation(.easeOut(duration: 0.25)) { smoothed = 0 } }
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize, phase: TimeInterval) {
        guard size.width > 0 else { return }

        let midY = size.height / 2
        let minHalf: CGFloat = 1.5
        let maxHalf = size.height / 2

        var offsets: [CGFloat] = []
        offsets.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let position = Double(index) / Double(sampleCount - 1)
            let amplitude = amplitude(at: position, phase: phase)
            offsets.append(minHalf + (maxHalf - minHalf) * amplitude)
        }

        func x(_ index: Int) -> CGFloat {
            size.width * CGFloat(index) / CGFloat(sampleCount - 1)
        }

        var ribbon = Path()
        ribbon.move(to: CGPoint(x: 0, y: midY - offsets[0]))
        for index in 1..<sampleCount {
            ribbon.addLine(to: CGPoint(x: x(index), y: midY - offsets[index]))
        }
        for index in stride(from: sampleCount - 1, through: 0, by: -1) {
            ribbon.addLine(to: CGPoint(x: x(index), y: midY + offsets[index]))
        }
        ribbon.closeSubpath()

        context.fill(ribbon, with: .color(tint.opacity(fillOpacity)))
        context.stroke(ribbon, with: .color(tint.opacity(strokeOpacity)), lineWidth: 1)

        guard isAnimating,
              let crest = offsets.indices.max(by: { offsets[$0] < offsets[$1] }),
              offsets[crest] > minHalf * 3
        else { return }

        let dot = CGRect(
            x: x(crest) - 2,
            y: midY - offsets[crest] - 2,
            width: 4,
            height: 4
        )
        context.fill(Path(ellipseIn: dot), with: .color(tint.opacity(0.9)))
    }

    private func amplitude(at position: Double, phase: TimeInterval) -> Double {
        guard isAnimating else { return 0 }

        let window = pow(sin(Double.pi * position), 0.3)

        let speed: Double = mode == .listening ? 5.2 : 1.9
        let travel = phase * speed
        let wave =
            0.62 * sin(travel + position * 7.4)
            + 0.38 * sin(travel * 1.63 - position * 4.1)

        let envelope = 0.45 + 0.55 * ((wave + 1) / 2)
        let drive: Double = mode == .listening ? (0.26 + 0.74 * smoothed) : 0.30

        return max(0, min(1, window * envelope * drive))
    }

    private var tint: Color {
        switch mode {
        case .thinking: return .ppMuted
        case .listening, .idle: return .ppAccent
        }
    }

    private var fillOpacity: Double {
        switch mode {
        case .idle: return 0.10
        case .thinking: return 0.14
        case .listening: return 0.20
        }
    }

    private var strokeOpacity: Double {
        switch mode {
        case .idle: return 0.25
        case .thinking: return 0.45
        case .listening: return 0.75
        }
    }
}

#Preview("All states") {
    VStack(alignment: .leading, spacing: PPSpacing.xl) {
        Group {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Idle").font(.ppCaption).foregroundStyle(Color.ppMuted)
                PPVoiceWave(mode: .idle)
            }
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Thinking").font(.ppCaption).foregroundStyle(Color.ppMuted)
                PPVoiceWave(mode: .thinking)
            }
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Listening — quiet").font(.ppCaption).foregroundStyle(Color.ppMuted)
                PPVoiceWave(level: 0.15, mode: .listening)
            }
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Listening — loud").font(.ppCaption).foregroundStyle(Color.ppMuted)
                PPVoiceWave(level: 0.9, mode: .listening, height: 40)
            }
        }
    }
    .padding(PPSpacing.xl)
    .ppScreenBackground()
}

#Preview("Live sweep") {
    struct Harness: View {
        @State private var level: Double = 0
        var body: some View {
            VStack(spacing: PPSpacing.xl) {
                PPVoiceWave(level: level, mode: .listening, height: 44)
                Slider(value: $level, in: 0...1).tint(Color.ppAccent)
                Text("level \(level, format: .number.precision(.fractionLength(2)))")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
            }
            .padding(PPSpacing.xl)
            .ppScreenBackground()
            .task {
                while !Task.isCancelled {
                    for value in stride(from: 0.0, through: 1.0, by: 0.08) {
                        level = value * Double.random(in: 0.6...1)
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    for value in stride(from: 1.0, through: 0.0, by: -0.12) {
                        level = value * 0.7
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
        }
    }
    return Harness()
}
