import SwiftUI

/// First-run setup, shown once after sign-up (gated on `currentUser.onboarded`).
/// Collects a display name, the role being prepared for, and a starter theme,
/// then PATCHes the profile and flips `onboarded` so the tabs take over.
struct OnboardingView: View {

    @EnvironmentObject private var auth: AuthViewModel
    @Bindable private var theme = ThemeStore.shared

    @State private var name = ""
    @State private var role = ""

    private let roleSuggestions = [
        "Backend Engineer", "Frontend Engineer", "Full-Stack Engineer",
        "iOS Engineer", "Data Analyst", "SDE",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.xxl) {
                header
                nameSection
                roleSection
                themeSection
                errorBanner
                getStartedButton
            }
            .padding(PPSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .onAppear {
            // Prefill anything captured at sign-up.
            name = auth.currentUser?.fullName ?? ""
            role = auth.currentUser?.targetRole ?? ""
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text("Let's set you up.")
                .font(.ppDisplay)
            Text("A couple of details so Placement Prep can tailor your practice.")
                .font(.ppBody)
                .foregroundStyle(Color.ppMuted)
        }
        .padding(.top, PPSpacing.xxl)
    }

    private var nameSection: some View {
        PPTextField(
            label: "Your name",
            placeholder: "e.g. Aditi Sharma",
            text: $name,
            textContentType: .name,
            autocapitalization: .words
        )
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPTextField(
                label: "What are you preparing for?",
                placeholder: "e.g. Backend Engineer",
                text: $role,
                submitLabel: .done
            )
            FlowRow(spacing: PPSpacing.sm) {
                ForEach(roleSuggestions, id: \.self) { suggestion in
                    PPFilterChip(title: suggestion, isSelected: role == suggestion) {
                        role = suggestion
                    }
                }
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            Text("Pick a starter theme").ppSectionLabelStyle()
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: PPSpacing.md),
                          GridItem(.flexible(), spacing: PPSpacing.md)],
                spacing: PPSpacing.md
            ) {
                ForEach(AppTheme.allCases) { option in
                    themeCard(option)
                }
            }
        }
    }

    private func themeCard(_ option: AppTheme) -> some View {
        let isSelected = !theme.isDynamic && theme.activeTheme == option
        return Button {
            withAnimation(PPMotion.settle) {
                theme.isDynamic = false
                theme.selection = option
            }
        } label: {
            VStack(spacing: PPSpacing.sm) {
                ThemeSwatch(palette: option.palette)
                Text(option.name)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppText)
            }
            .frame(maxWidth: .infinity)
            .padding(PPSpacing.md)
            .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.lg)
                    .strokeBorder(isSelected ? Color.ppAccent : Color.ppBorder,
                                  lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = auth.errorMessage {
            HStack(alignment: .top, spacing: PPSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.ppHard)
                Text(message)
                    .font(.ppCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PPSpacing.md)
            .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.md)
                    .strokeBorder(Color.ppHard.opacity(0.4), lineWidth: 1)
            }
        }
    }

    private var getStartedButton: some View {
        Button(action: submit) {
            if auth.isLoading {
                ProgressView().tint(.ppOnAccent)
            } else {
                Text("Get started")
            }
        }
        .buttonStyle(.ppPrimary)
        .disabled(!canSubmit || auth.isLoading)
        .opacity(canSubmit || auth.isLoading ? 1 : 0.5)
        .animation(PPMotion.snappy, value: canSubmit)
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        guard canSubmit, !auth.isLoading else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedRole = role.trimmingCharacters(in: .whitespaces)
        Task { await auth.completeOnboarding(fullName: trimmedName, targetRole: trimmedRole) }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AuthViewModel())
}
