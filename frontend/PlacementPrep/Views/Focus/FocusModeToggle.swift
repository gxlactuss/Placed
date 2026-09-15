import SwiftUI

struct FocusModeToggle: View {
    var compact = false

    @Environment(FocusModeStore.self) private var focus
    @State private var showBriefing = false

    var body: some View {
        Button {
            if focus.hasSeenBriefing {
                withAnimation(PPMotion.snappy) { focus.toggle() }
            } else {
                showBriefing = true
            }
        } label: {
            if compact { icon.frame(width: 36, height: 36) } else { pill }
        }
        .buttonStyle(.plain)
        .background(background, in: .capsule)
        .overlay { Capsule().strokeBorder(border, lineWidth: 1) }
        .accessibilityLabel("Focus mode")
        .accessibilityValue(focus.isOn ? "On" : "Off")
        .accessibilityAddTraits(focus.isOn ? [.isSelected, .isButton] : .isButton)
        .sheet(isPresented: $showBriefing) { FocusModeBriefing() }
    }

    private var pill: some View {
        HStack(spacing: PPSpacing.xs) {
            icon
            Text("Focus").font(.ppCaption)
        }
        .padding(.horizontal, PPSpacing.md)
        .frame(height: 36)
    }

    private var icon: some View {
        Image(systemName: focus.isOn ? "moon.zzz.fill" : "moon.zzz")
            .font(.system(size: 14, weight: .medium))
    }

    private var foreground: Color { focus.isOn ? .ppAccent400 : .ppMuted }
    private var background: Color { focus.isOn ? .ppAccentSection : .ppSurface }
    private var border: Color { focus.isOn ? .ppAccent700.opacity(0.55) : .ppBorder }
}

struct FocusModeBriefing: View {

    @Environment(FocusModeStore.self) private var focus
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.xl) {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Focus mode").font(.ppTitle)
                Text("Fewer interruptions while you practise.")
                    .font(.ppBody)
                    .foregroundStyle(Color.ppMuted)
            }

            VStack(spacing: PPSpacing.md) {
                row(
                    icon: "iphone.gen3",
                    title: "Keeps the screen awake",
                    detail: "Your phone won't sleep mid-answer during a voice round."
                )
                row(
                    icon: "moon.zzz.fill",
                    title: "Do Not Disturb is up to you",
                    detail: "iOS doesn't let any app switch Focus on for you. Swipe down for Control Centre → Focus, or set up the automation below once."
                )
            }

            automationCard

            Spacer(minLength: 0)

            VStack(spacing: PPSpacing.md) {
                Button("Turn on Focus") {
                    focus.markBriefed()
                    focus.setOn(true)
                    dismiss()
                }
                .buttonStyle(.ppPrimary)

                Button("Not now") {
                    focus.markBriefed()
                    dismiss()
                }
                .buttonStyle(.ppSecondary)
            }
        }
        .padding(PPSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ppGround.ignoresSafeArea())
        .foregroundStyle(Color.ppText)
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
    }

    private var automationCard: some View {
        PPCard {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                Text("Automate it (once)")
                    .ppSectionLabelStyle()

                Text("In Shortcuts → Automation → New → **App**, choose PlacementPrep and *Is Opened*, then add the **Set Focus** action.")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                        .font(.ppCaption)
                }
                .buttonStyle(.ppInlineLink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: PPSpacing.lg) {
            PPIconTile(systemName: icon, tint: .ppAccent400)

            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                Text(title).font(.ppHeadline)
                Text(detail)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview("Toggle") {
    VStack(spacing: PPSpacing.xl) {
        FocusModeToggle()
            .environment(FocusModeStore.preview(on: false))
        FocusModeToggle()
            .environment(FocusModeStore.preview(on: true))
        FocusModeToggle(compact: true)
            .environment(FocusModeStore.preview(on: true))
    }
    .padding(PPSpacing.xl)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}

#Preview("Briefing") {
    FocusModeBriefing()
        .environment(FocusModeStore.preview(briefed: false))
}
