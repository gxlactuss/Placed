import SwiftUI

/// A live voice wave for the mock interview, in the manner of an assistant's
/// listening indicator.
///
/// Two deliberate restraints keep it inside the Ledger rules. It is drawn as
/// flat capsules with no gradient and no glow, and it never becomes the loud
/// element on the screen --- while recording, the microphone button already owns
/// that role, so this sits at reduced opacity and reads as ambient feedback
/// rather than as a control.
///
/// The bars follow a *travelling* wave rather than jumping independently: each
/// bar samples two sine components at different frequencies, offset by its own
/// position, so the crest moves along the strip. An equaliser that reacts
/// per-bar looks mechanical; a travelling wave looks like speech. A raised-sine
/// window tapers both ends to nothing, which is what makes it read as one
/// contained wave instead of a full-width meter.
struct PPVoiceWave: View {

    enum Mode: Equatable {
        /// Nothing happening --- a flat resting line.
        case idle
        /// The microphone is live; amplitude tracks `level`.
        case listening
        /// Waiting on the model. A slow, low travelling wave so the strip stays
        /// alive without implying it can hear anything.
        case thinking
    }

    /// Normalised microphone level, 0...1. Ignored unless `mode` is `.listening`.
    var level: Double = 0
    var mode: Mode = .idle
    var barCount: Int = 26
    var height: CGFloat = 26

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
        guard barCount > 1, size.width > 0 else { return }

        let barWidth = max(2, size.width / CGFloat(barCount) * 0.42)
        let spacing = (size.width - barWidth * CGFloat(barCount)) / CGFloat(barCount - 1)
        let midY = size.height / 2
        // A visible resting line, so the strip never disappears entirely.
        let minHeight = max(2, barWidth)

        for index in 0..<barCount {
            let position = Double(index) / Double(barCount - 1)
            let amplitude = amplitude(at: position, phase: phase)
            let barHeight = minHeight + (size.height - minHeight) * amplitude
            let x = CGFloat(index) * (barWidth + spacing)

            let rect = CGRect(
                x: x,
                y: midY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(tint.opacity(opacity(for: amplitude)))
            )
        }
    }

    /// Height of one bar, 0...1, at normalised position `position` along the strip.
    private func amplitude(at position: Double, phase: TimeInterval) -> Double {
        guard isAnimating else { return 0 }

        // Ends taper to nothing, so the wave is contained rather than full-width.
        // Raised to a fractional power to flatten the middle: a plain sine window
        // concentrates all the height in the centre few bars and the strip reads
        // as a lump rather than a wave.
        let window = pow(sin(Double.pi * position), 0.55)

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
        let drive: Double = mode == .listening ? (0.20 + 0.80 * smoothed) : 0.20

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

    /// Taller bars sit slightly stronger, which gives the crest definition
    /// without resorting to a gradient.
    private func opacity(for amplitude: Double) -> Double {
        switch mode {
        case .idle: return 0.18
        case .thinking: return 0.28 + 0.22 * amplitude
        case .listening: return 0.42 + 0.38 * amplitude
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
                PPVoiceWave(level: 0.9, mode: .listening)
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
                PPVoiceWave(level: level, mode: .listening, height: 34)
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
