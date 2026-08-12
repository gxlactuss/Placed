import SwiftUI

/// The live voice visualiser for the mock interview.
///
/// Drawn as a **mirrored ribbon**: one travelling wave forms the top edge and
/// its mirror forms the bottom, closing into a single lens-shaped body that
/// swells where the voice is loud and pinches where it isn't. It replaced a row
/// of independent bars, which read as a meter — a piece of equipment measuring
/// you — where a continuous body reads as a voice.
///
/// It stays inside the Ledger rules by other means than flatness: one hue, no
/// second colour, and the structure comes from a **hairline stroke** over a low
/// fill, which is the same trick every card in the app uses for depth. The
/// crest dot is the only bright mark, and it exists so the eye has something to
/// follow along the strip.
///
/// The wave travels rather than each sample jumping in place: every point along
/// the ribbon samples two sine components at unrelated frequencies offset by its
/// own position, so the crest moves. A raised-sine window tapers both ends to
/// nothing, which is what contains it into a shape instead of a full-width band.
struct PPVoiceWave: View {

    enum Mode: Equatable {
        /// Nothing happening — a flat resting line.
        case idle
        /// The microphone is live; amplitude tracks `level`.
        case listening
        /// Waiting on the model. A slow, shallow ripple so the strip stays alive
        /// without implying it can hear anything.
        case thinking
    }

    /// Normalised microphone level, 0...1. Ignored unless `mode` is `.listening`.
    var level: Double = 0
    var mode: Mode = .idle
    var height: CGFloat = 26

    /// How many points the ribbon is sampled at. Dense enough that straight
    /// segments between them read as a smooth curve, which is far cheaper than
    /// fitting splines every frame.
    private let sampleCount = 96

    /// Exponentially smoothed level. The meter updates at 20 Hz and raw values
    /// jitter hard enough to look like a fault, so each sample is blended into
    /// the previous one and tweened over the gap between samples.
    @State private var smoothed: Double = 0

    private var isAnimating: Bool { mode != .idle }

    var body: some View {
        Group {
            if isAnimating {
                // Only subscribe to the frame clock while there is something to
                // animate; idle would otherwise redraw forever for a flat line.
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
        // Seed from the current level rather than waiting for it to change: a
        // recorder that reports a steady level, or a view that appears with one
        // already set, would otherwise draw a flat line forever.
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

    // MARK: - Drawing

    private func draw(in context: GraphicsContext, size: CGSize, phase: TimeInterval) {
        guard size.width > 0 else { return }

        let midY = size.height / 2
        // Never fully closes: a hairline of body remains so the ribbon reads as
        // a resting voice rather than as nothing at all.
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

        // One closed path: forwards along the top edge, back along its mirror.
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

        // The crest: the tallest point of the ribbon, marked so the eye has
        // something to follow as the wave travels. Suppressed at rest, where
        // there is no crest to speak of.
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

    /// Half-height of the ribbon, 0...1, at normalised position `position`.
    private func amplitude(at position: Double, phase: TimeInterval) -> Double {
        guard isAnimating else { return 0 }

        // Ends taper to nothing, so the wave is contained rather than full-width.
        // The exponent is low so the taper happens fast at the very ends and the
        // middle stays broad — a higher one pinches the whole ribbon into a
        // needle, which is what it looked like before this was tuned.
        let window = pow(sin(Double.pi * position), 0.3)

        let speed: Double = mode == .listening ? 5.2 : 1.9
        let travel = phase * speed
        // Two components at unrelated frequencies, so the shape never visibly
        // repeats the way a single sine does.
        let wave =
            0.62 * sin(travel + position * 7.4)
            + 0.38 * sin(travel * 1.63 - position * 4.1)

        // Ride the wave on a baseline rather than using it as a bare multiplier.
        // Multiplying three sub-1 terms together means the peaks only coincide by
        // luck, and loud speech never actually fills the strip.
        let envelope = 0.45 + 0.55 * ((wave + 1) / 2)
        // The floor gives the ribbon a body at rest — below about a quarter the
        // two edges meet and it reads as a line, not a voice — while the rest of
        // the range is left to the level, so loud and quiet actually differ.
        let drive: Double = mode == .listening ? (0.26 + 0.74 * smoothed) : 0.30

        return max(0, min(1, window * envelope * drive))
    }

    private var tint: Color {
        switch mode {
        // Muted while thinking: the strip is alive but nothing is being heard,
        // and the accent would overstate that.
        case .thinking: return .ppMuted
        case .listening, .idle: return .ppAccent
        }
    }

    /// The body stays quiet and the outline carries the shape — the same
    /// hairline-over-fill relationship the cards use.
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

// MARK: - Previews

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

/// Sweeps the level so the smoothing and travel can be judged in motion, which
/// a static preview cannot show.
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
