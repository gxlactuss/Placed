import SwiftUI

struct InterviewHeroCard: View {

    let onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                Text("AI Mock Interview")
                    .font(.ppSectionLabel)
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(Color.ppAccent400)

                Text("Practice the real thing.")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                PPLiquidWave(mode: .ambient, height: 34)
                    .padding(.horizontal, -PPSpacing.xl)

                startPill
                    .padding(.top, PPSpacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PPSpacing.xl)
            .background {
                ZStack {
                    Color.ppAccentSection
                    LinearGradient(
                        colors: [Color.ppAccent.opacity(0.16), Color.ppAccent.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .clipShape(.rect(cornerRadius: PPRadius.xl))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.xl)
                    .strokeBorder(Color.ppAccent700.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.ppPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI mock interview. Practice the real thing.")
        .accessibilityHint("Starts a round")
        .accessibilityAddTraits(.isButton)
    }

    private var startPill: some View {
        HStack(spacing: PPSpacing.sm) {
            Image(systemName: "mic.fill")
            Text("Start round")
            Spacer(minLength: PPSpacing.sm)
            Image(systemName: "arrow.right")
        }
        .font(.ppBodyMedium)
        .foregroundStyle(Color.ppOnAccent)
        .padding(.horizontal, PPSpacing.xl)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Color.ppAccent, in: .capsule)
    }
}
