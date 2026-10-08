import SwiftUI

struct AccountSettingsView: View {

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Bindable private var theme = ThemeStore.shared
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: PPSpacing.lg) {
                    profileCard

                    PPSectionHeader("Danger zone")
                        .padding(.top, PPSpacing.lg)

                    errorBanner
                    deleteRow
                }
                .padding(PPSpacing.xl)
                .ppContentColumn()
                .animation(PPMotion.settle, value: auth.errorMessage)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.ppGround.ignoresSafeArea())
        .foregroundStyle(Color.ppText)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(theme.activeTheme.palette.colorScheme)
        .interactiveDismissDisabled(auth.isDeletingAccount)
        .onAppear { auth.errorMessage = nil }
        .onDisappear {
            if !auth.isDeletingAccount { auth.errorMessage = nil }
        }
        .alert("Delete your account?", isPresented: $showDeleteConfirmation) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, your progress, interview history and resume reviews. This can't be undone.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Account").font(.ppTitle)
            Spacer()
            Button("Done") { dismiss() }
                .font(.ppBodyMedium)
                .foregroundStyle(Color.ppAccent400)
                .disabled(auth.isDeletingAccount)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.xl)
        .padding(.bottom, PPSpacing.md)
    }

    private var profileCard: some View {
        PPCard {
            HStack(spacing: PPSpacing.lg) {
                PPIconTile(systemName: "person.crop.circle", tint: .ppAccent400)

                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    Text(displayName).font(.ppHeadline)
                    if let email = auth.currentUser?.email {
                        Text(email)
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signed in as \(displayName)\(auth.currentUser.map { ", \($0.email)" } ?? "")")
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = auth.errorMessage {
            HStack(alignment: .top, spacing: PPSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.ppHard)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PPSpacing.md)
            .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.md)
                    .strokeBorder(Color.ppHard.opacity(0.4), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Couldn't delete account. \(message)")
            .transition(.opacity)
        }
    }

    private var deleteRow: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            PPCard(padding: PPSpacing.md) {
                HStack(spacing: PPSpacing.lg) {
                    PPIconTile(systemName: "trash", tint: .ppHard)

                    VStack(alignment: .leading, spacing: PPSpacing.xs) {
                        Text(auth.isDeletingAccount ? "Deleting account…" : "Delete account")
                            .font(.ppHeadline)
                            .foregroundStyle(Color.ppHard)
                        Text("Permanently removes your account and everything saved with it.")
                            .font(.ppCaption)
                            .foregroundStyle(Color.ppMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: PPSpacing.sm)

                    if auth.isDeletingAccount {
                        ProgressView().tint(Color.ppHard)
                    }
                }
            }
        }
        .buttonStyle(.ppPressable)
        .disabled(auth.isDeletingAccount)
        .overlay {
            RoundedRectangle(cornerRadius: PPRadius.lg)
                .strokeBorder(Color.ppHard.opacity(0.35), lineWidth: 1)
        }
        .accessibilityLabel(auth.isDeletingAccount ? "Deleting account" : "Delete account")
        .accessibilityHint(
            auth.isDeletingAccount
                ? "Please wait."
                : "Permanently deletes your account, progress, interview history and resume reviews. You'll be asked to confirm."
        )
    }

    // MARK: - Actions

    private func deleteAccount() async {
        let deleted = await auth.deleteAccount()
        if deleted {
            PPHaptics.success()
        } else {
            PPHaptics.miss()
        }
    }

    private var displayName: String {
        let name = auth.currentUser?.fullName?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Your account" : name
    }
}

#Preview("Account") {
    Color.ppGround
        .sheet(isPresented: .constant(true)) {
            AccountSettingsView()
                .environmentObject(AuthViewModel())
        }
}
