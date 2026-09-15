import SwiftUI
import UIKit

struct AppIconPickerView: View {

    @Environment(XPStore.self) private var xp
    @Environment(\.dismiss) private var dismiss

    @State private var appliedLevel = AppIconService.currentLevel

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: PPSpacing.md) {
                    balanceLine

                    ForEach(XPLevel.allCases) { level in
                        AppIconRow(
                            level: level,
                            isUnlocked: xp.isUnlocked(level),
                            isApplied: appliedLevel == level,
                            xpNeeded: max(0, level.minimumXP - xp.total)
                        ) {
                            Task {
                                if await AppIconService.apply(level) {
                                    withAnimation(PPMotion.settle) {
                                        appliedLevel = AppIconService.currentLevel
                                    }
                                }
                            }
                        }
                        .disabled(!xp.isUnlocked(level))
                    }

                    if !AppIconService.isAvailable {
                        unsupportedNote
                    }
                }
                .padding(PPSpacing.xl)
                .ppContentColumn()
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.ppGround.ignoresSafeArea())
        .foregroundStyle(Color.ppText)
        .presentationDetents([.fraction(0.9), .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Text("App icon").font(.ppTitle)
            Spacer()
            Button("Done") { dismiss() }
                .font(.ppBodyMedium)
                .foregroundStyle(Color.ppAccent400)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.xl)
        .padding(.bottom, PPSpacing.md)
    }

    private var balanceLine: some View {
        PPCard {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                (
                    Text("\(xp.total)")
                        .font(.ppStat())
                        .foregroundStyle(Color.ppAccent)
                    + Text(" XP · \(xp.level.title)")
                        .font(.ppHeadline)
                )
                PPProgressBar(progress: xp.progressInLevel)
                if let next = xp.nextLevel, let remaining = xp.xpToNextLevel {
                    Text("\(remaining) XP unlocks the \(next.title) icon")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                } else {
                    Text("Every icon unlocked")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                }
            }
        }
    }

    private var unsupportedNote: some View {
        Text("This device won't let apps change their icon, so your pick can't be applied here.")
            .font(.ppCaption)
            .foregroundStyle(Color.ppMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, PPSpacing.xs)
    }
}

private struct AppIconRow: View {

    let level: XPLevel
    let isUnlocked: Bool
    let isApplied: Bool
    let xpNeeded: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PPCard(tone: isApplied ? .elevated : .surface, padding: PPSpacing.md) {
                HStack(spacing: PPSpacing.lg) {
                    iconTile

                    VStack(alignment: .leading, spacing: PPSpacing.xs) {
                        Text(level.title).font(.ppHeadline)
                        Text(subtitle)
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                    }

                    Spacer(minLength: PPSpacing.sm)

                    trailingMark
                }
            }
        }
        .buttonStyle(.ppPressable)
        .opacity(isUnlocked ? 1 : 0.55)
        .overlay {
            if isApplied {
                RoundedRectangle(cornerRadius: PPRadius.lg)
                    .strokeBorder(Color.ppAccent, lineWidth: 1.5)
            }
        }
    }

    private var subtitle: String {
        if isUnlocked {
            return level.minimumXP == 0 ? "The one you started with" : "Unlocked at \(level.minimumXP) XP"
        }
        return "\(xpNeeded) XP to go"
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PPRadius.md)
                .fill(Color.ppElevated)

            if isUnlocked {
                Image(level.previewImageName)
                    .resizable()
                    .scaledToFill()
                    .clipShape(.rect(cornerRadius: PPRadius.md))
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.ppMuted)
            }
        }
        .frame(width: 54, height: 54)
        .overlay {
            RoundedRectangle(cornerRadius: PPRadius.md)
                .strokeBorder(Color.ppBorderStrong, lineWidth: 1)
        }
    }

    private var trailingMark: some View {
        ZStack {
            Circle()
                .strokeBorder(isApplied ? Color.clear : Color.ppBorderStrong, lineWidth: 1.5)
            if isApplied {
                Circle().fill(Color.ppAccent)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.ppOnAccent)
            }
        }
        .frame(width: 24, height: 24)
    }
}

#Preview("Icon picker") {
    Color.ppGround
        .sheet(isPresented: .constant(true)) {
            AppIconPickerView()
                .environment(XPStore.preview(total: 120))
        }
}
