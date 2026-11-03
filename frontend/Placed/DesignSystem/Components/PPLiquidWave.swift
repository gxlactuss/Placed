import Metal
import SwiftUI

struct PPLiquidWave: View {

    enum Mode: Equatable {
        case idle
        case listening
        case thinking
        /// A slow, steady swell for decorative use outside a round.
        case ambient
    }

    var level: Double = 0
    var mode: Mode = .idle
    var height: CGFloat = 72

    private static let canRunShader = MTLCreateSystemDefaultDevice() != nil

    @State private var filter = MotionFilter()
    @State private var start = Date()

    var body: some View {
        Group {
            if Self.canRunShader {
                shaderBody
            } else {
                PPVoiceWave(level: level, mode: fallbackMode, height: height)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var shaderBody: some View {
        TimelineView(.animation) { timeline in
            let frame = filter.tick(
                at: timeline.date.timeIntervalSince(start),
                targetLevel: targetLevel,
                targetSpeed: targetSpeed
            )

            GeometryReader { geometry in
                Rectangle()
                    .fill(.white)
                    .colorEffect(
                        ShaderLibrary.ppLiquidWave(
                            .float2(geometry.size),
                            .float(Float(frame.phase)),
                            .float(Float(frame.level)),
                            .color(tint)
                        )
                    )
            }
        }
    }

    private var targetLevel: Double {
        switch mode {
        case .idle: 0.05
        case .ambient: 0.3
        case .thinking: 0.24
        case .listening: min(max(level, 0), 1)
        }
    }

    private var targetSpeed: Double {
        switch mode {
        case .idle: 0.12
        case .ambient: 0.2
        case .thinking: 0.34
        case .listening: 0.95
        }
    }

    private var tint: Color {
        switch mode {
        case .thinking: .ppMuted
        case .listening, .idle, .ambient: .ppAccent
        }
    }

    private var fallbackMode: PPVoiceWave.Mode {
        switch mode {
        case .idle, .ambient: .idle
        case .listening: .listening
        case .thinking: .thinking
        }
    }
}

@MainActor
private final class MotionFilter {

    struct Frame {
        var phase: Double
        var level: Double
    }

    private var level: Double = 0
    private var speed: Double = 0
    private var phase: Double = 0
    private var lastElapsed: Double?

    func tick(at elapsed: Double, targetLevel: Double, targetSpeed: Double) -> Frame {
        let delta = min(max(elapsed - (lastElapsed ?? elapsed), 0), 1.0 / 30)
        lastElapsed = elapsed

        let levelTau = targetLevel > level ? 0.055 : 0.30
        level += (targetLevel - level) * approach(delta: delta, tau: levelTau)
        speed += (targetSpeed - speed) * approach(delta: delta, tau: 0.45)

        phase += delta * speed

        return Frame(phase: phase, level: level)
    }

    private func approach(delta: Double, tau: Double) -> Double {
        1 - exp(-delta / tau)
    }
}

#Preview("All states") {
    VStack(alignment: .leading, spacing: PPSpacing.xl) {
        Group {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Idle").font(.ppCaption).foregroundStyle(Color.ppMuted)
                PPLiquidWave(mode: .idle)
            }
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Thinking").font(.ppCaption).foregroundStyle(Color.ppMuted)
                PPLiquidWave(mode: .thinking)
            }
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Listening (quiet)").font(.ppCaption).foregroundStyle(Color.ppMuted)
                PPLiquidWave(level: 0.15, mode: .listening)
            }
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Listening (loud)").font(.ppCaption).foregroundStyle(Color.ppMuted)
                PPLiquidWave(level: 0.9, mode: .listening, height: 60)
            }
        }
    }
    .padding(PPSpacing.xl)
    .ppScreenBackground()
}

#Preview("Live sweep") {
    struct Harness: View {
        @State private var level: Double = 0
        @State private var mode: PPLiquidWave.Mode = .listening

        var body: some View {
            VStack(spacing: PPSpacing.xl) {
                PPLiquidWave(level: level, mode: mode, height: 72)

                Slider(value: $level, in: 0...1).tint(Color.ppAccent)

                HStack(spacing: PPSpacing.sm) {
                    ForEach(["idle", "listening", "thinking"], id: \.self) { name in
                        Button(name) {
                            mode = switch name {
                            case "idle": .idle
                            case "thinking": .thinking
                            default: .listening
                            }
                        }
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppAccent)
                    }
                }

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
