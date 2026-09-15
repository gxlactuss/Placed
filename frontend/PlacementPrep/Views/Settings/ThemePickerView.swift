import SwiftUI

struct ThemePickerView: View {

    @Bindable private var store = ThemeStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: PPSpacing.md) {
                    dynamicRow

                    ForEach(AppTheme.allCases) { theme in
                        ThemeOptionRow(
                            theme: theme,
                            isSelected: store.activeTheme == theme
                        ) {
                            withAnimation(PPMotion.settle) { store.selection = theme }
                        }
                        .disabled(store.isDynamic)
                        .opacity(store.isDynamic ? 0.45 : 1)
                    }
                }
                .padding(PPSpacing.xl)
                .ppContentColumn()
                .animation(PPMotion.settle, value: store.isDynamic)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.ppGround.ignoresSafeArea())
        .foregroundStyle(Color.ppText)
        .presentationDetents([.fraction(0.9), .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(store.activeTheme.palette.colorScheme)
    }

    private var dynamicRow: some View {
        PPCard {
            HStack(spacing: PPSpacing.lg) {
                PPIconTile(systemName: "circle.lefthalf.filled", tint: .ppAccent400)

                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    Text("Dynamic theme").font(.ppHeadline)
                    Text("Follows the time of day — Coral Drive from 7am, Amber from 7pm.")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: PPSpacing.sm)

                Toggle("", isOn: $store.isDynamic)
                    .labelsHidden()
                    .tint(.ppAccent)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Theme").font(.ppTitle)
            Spacer()
            Button("Done") { dismiss() }
                .font(.ppBodyMedium)
                .foregroundStyle(Color.ppAccent400)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.xl)
        .padding(.bottom, PPSpacing.md)
    }
}

private struct ThemeOptionRow: View {

    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PPCard(tone: isSelected ? .elevated : .surface, padding: PPSpacing.md) {
                HStack(spacing: PPSpacing.lg) {
                    ThemeSwatch(palette: theme.palette)

                    Text(theme.name).font(.ppHeadline)

                    Spacer(minLength: PPSpacing.sm)

                    ZStack {
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.clear : Color.ppBorderStrong,
                                lineWidth: 1.5
                            )
                        if isSelected {
                            Circle().fill(Color.ppAccent)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.ppOnAccent)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
            }
        }
        .buttonStyle(.ppPressable)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: PPRadius.lg)
                    .strokeBorder(Color.ppAccent, lineWidth: 1.5)
            }
        }
    }
}

struct ThemeSwatch: View {

    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(palette.text)
                .frame(width: 34, height: 5)

            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette.accent)
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(palette.muted).frame(width: 26, height: 3)
                    Capsule().fill(palette.muted.opacity(0.5)).frame(width: 18, height: 3)
                }
            }
            .padding(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5).strokeBorder(palette.border, lineWidth: 1)
            }

            Capsule().fill(palette.accent).frame(width: 36, height: 8)
        }
        .padding(8)
        .frame(width: 88, height: 58, alignment: .leading)
        .background(palette.ground, in: .rect(cornerRadius: PPRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: PPRadius.md)
                .strokeBorder(palette.borderStrong, lineWidth: 1)
        }
    }
}

#Preview("Theme picker") {
    Color.ppGround
        .sheet(isPresented: .constant(true)) {
            ThemePickerView()
        }
}

#Preview("Swatches") {
    HStack(spacing: PPSpacing.md) {
        ForEach(AppTheme.allCases) { theme in
            ThemeSwatch(palette: theme.palette)
        }
    }
    .padding(PPSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ppScreenBackground()
}
