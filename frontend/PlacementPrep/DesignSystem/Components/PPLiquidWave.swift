import Metal
import SwiftUI

/// The live voice visualiser for the mock interview, drawn as a body of liquid
/// **hanging from the top edge of its frame**.
///
/// A Metal fragment shader (`Shaders/PPLiquidWave.metal`) fills it: two passes
/// of simplex noise displace the coordinates of a third — a **domain warp** — so
/// the field folds over itself into lobes and filaments, and the microphone
/// level controls both how hard it folds and how far down it reaches. Silence
/// barely stirs; a loud answer churns and floods down the screen.
///
/// It hangs rather than floats because it is chrome, not an instrument: attached
/// to the edge above and spanning the full width, it reads as part of the screen
/// the voice is disturbing. Give it the full width — inset, the header it's
/// meant to be attached to shows either side of it and the illusion goes.
/// `PPVoiceWave`'s drawn ribbon stays as the fallback for any device that can't
/// give us a Metal device.
///
/// It obeys the Ledger rules the same way the ribbon does: **one hue**, taken
/// from the theme accent and passed into the shader, with all of the life coming
/// from motion and alpha rather than from a second colour. Resist the pull to
/// mix in a second hue here — the reference this was built from cycled blue,
/// purple and green, and that reads as somebody else's assistant sitting inside
/// the app.
///
/// Two details are what make it smooth, and both are easy to undo by accident:
///
/// - **The phase is accumulated, not computed.** The shader is fed a running
///   total of `elapsed × speed` rather than `now × speed`, because speed changes
///   with the mode — multiplying a large elapsed time by a new speed jumps the
///   animation to a different point in the noise field, which looks like a
///   dropped frame at exactly the moment the student stops speaking.
/// - **The level is refiltered every frame.** The meter behind it only reports
///   at 20 Hz, so handing it straight to a 120 Hz shader would step. The filter
///   below eases toward the newest reading with a fast attack and a slow
///   release, which is also how the ear reads loudness.
struct PPLiquidWave: View {

    enum Mode: Equatable {
        /// Nothing happening — a still, quiet body.
        case idle
        /// The microphone is live; the churn tracks `level`.
        case listening
        /// Waiting on the model. Slow motion at a fixed low energy, so the strip
        /// stays alive without implying it can hear anything.
        case thinking
    }

    /// Normalised microphone level, 0...1. Ignored unless `mode` is `.listening`.
    var level: Double = 0
    var mode: Mode = .idle
    var height: CGFloat = 72

    /// Resolved once: a device without a Metal device can't run the shader at
    /// all, and asking every frame would be wasteful.
    private static let canRunShader = MTLCreateSystemDefaultDevice() != nil

    @State private var filter = MotionFilter()
    /// The clock's origin. Held in state so it survives the parent redrawing —
    /// a `let` here would be reset by it, and the animation would jump.
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
            // Mutating the filter here is deliberate and safe: it is a plain
            // class with no observation on it, so this drives the shader's
            // arguments without invalidating the view and re-entering the body.
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

    // MARK: - Mode

    /// What the body should be doing, before smoothing. Every mode has *some*
    /// energy — the strip is never a dead rectangle — and the filter eases
    /// between them, so switching mode is a settle rather than a cut.
    private var targetLevel: Double {
        switch mode {
        case .idle: 0.05
        case .thinking: 0.24
        case .listening: min(max(level, 0), 1)
        }
    }

    /// Radians of noise per second. Thinking is deliberately much slower than
    /// listening: the same motion at speaking pace would suggest the app is
    /// hearing something while the student is silent.
    private var targetSpeed: Double {
        switch mode {
        case .idle: 0.12
        case .thinking: 0.34
        case .listening: 0.95
        }
    }

    private var tint: Color {
        switch mode {
        // Muted while thinking: the strip is alive but nothing is being heard,
        // and the accent would overstate that.
        case .thinking: .ppMuted
        case .listening, .idle: .ppAccent
        }
    }

    private var fallbackMode: PPVoiceWave.Mode {
        switch mode {
        case .idle: .idle
        case .listening: .listening
        case .thinking: .thinking
        }
    }
}

// MARK: - Motion filter

/// Turns a coarse, jumpy level into something a shader can be driven with.
///
/// A reference type on purpose: it is updated from inside a `TimelineView`'s
/// body, and a value in `@State` would either not persist the update or would
/// invalidate the view and re-enter that body every frame.
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
        // Clamped so a stall — a slow frame, or the app returning from the
        // background — advances the animation by one frame rather than lurching
        // through however many seconds it was away.
        let delta = min(max(elapsed - (lastElapsed ?? elapsed), 0), 1.0 / 30)
        lastElapsed = elapsed

        // Fast attack, slow release. A voice starting is an event worth tracking
        // immediately; a voice stopping should decay, because releasing the
        // level instantly makes every gap between words look like a fault.
        let levelTau = targetLevel > level ? 0.055 : 0.30
        level += (targetLevel - level) * approach(delta: delta, tau: levelTau)
        speed += (targetSpeed - speed) * approach(delta: delta, tau: 0.45)

        // Accumulated, never `elapsed * speed` — see the note on the view.
        phase += delta * speed

        return Frame(phase: phase, level: level)
    }

    /// The fraction of the remaining distance to close in `delta` seconds, for a
    /// filter with time constant `tau`. Framed this way so the smoothing is the
    /// same at 60 Hz and 120 Hz — a fixed per-frame blend would settle twice as
    /// fast on a ProMotion screen.
    private func approach(delta: Double, tau: Double) -> Double {
        1 - exp(-delta / tau)
    }
}

// MARK: - Previews

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
                Text("Listening — quiet").font(.ppCaption).foregroundStyle(Color.ppMuted)
                PPLiquidWave(level: 0.15, mode: .listening)
            }
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Listening — loud").font(.ppCaption).foregroundStyle(Color.ppMuted)
                PPLiquidWave(level: 0.9, mode: .listening, height: 60)
            }
        }
    }
    .padding(PPSpacing.xl)
    .ppScreenBackground()
}

/// Sweeps the level so the filtering and the warp can be judged in motion, which
/// a static preview cannot show. The mode picker is here because the settle
/// between modes is the part most likely to look wrong.
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
                // Rough stand-in for speech: bursts with pauses between them.
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
