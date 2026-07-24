import SwiftUI

/// The sign-in / sign-up gate shown until a JWT is in the Keychain. Composed
/// from `DesignSystem` primitives so it reads as the same editorial system as
/// the rest of the app: serif wordmark, hairline fields, one amber call to
/// action, everything else quiet.
struct AuthView: View {

    @EnvironmentObject private var auth: AuthViewModel

    private enum Mode { case login, signup }
    @State private var mode: Mode = .login

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var targetRole = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.xl) {
                brand
                fields
                errorBanner
                primaryButton
                modeToggle
            }
            .padding(PPSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .animation(PPMotion.settle, value: mode)
    }

    // MARK: - Brand

    private var brand: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text("PlacementPrep")
                .font(.ppDisplay)
            Text(mode == .login
                 ? "Welcome back. Let's get you interview-ready."
                 : "Create an account to track your prep.")
                .font(.ppBody)
                .foregroundStyle(Color.ppMuted)
        }
        .padding(.top, PPSpacing.xxl)
        .padding(.bottom, PPSpacing.sm)
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(spacing: PPSpacing.lg) {
            if mode == .signup {
                PPTextField(
                    label: "Name",
                    placeholder: "Your name",
                    text: $fullName,
                    textContentType: .name
                )
            }

            PPTextField(
                label: "Email",
                placeholder: "you@example.com",
                text: $email,
                keyboard: .emailAddress,
                textContentType: .emailAddress
            )

            PPTextField(
                label: "Password",
                placeholder: mode == .signup ? "At least 8 characters" : "Your password",
                text: $password,
                isSecure: true,
                textContentType: mode == .signup ? .newPassword : .password,
                submitLabel: mode == .signup ? .next : .go,
                onSubmit: { if mode == .login { submit() } }
            )

            if mode == .signup {
                PPTextField(
                    label: "Target role (optional)",
                    placeholder: "e.g. Backend Engineer",
                    text: $targetRole,
                    submitLabel: .go,
                    onSubmit: submit
                )
            }
        }
    }

    // MARK: - Error

    @ViewBuilder
    private var errorBanner: some View {
        if let message = auth.errorMessage {
            HStack(alignment: .top, spacing: PPSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.ppHard)
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
            .transition(.opacity)
        }
    }

    // MARK: - Primary CTA

    private var primaryButton: some View {
        Button(action: submit) {
            if auth.isLoading {
                ProgressView()
                    .tint(.ppOnAccent)
            } else {
                Text(mode == .login ? "Log in" : "Create account")
            }
        }
        .buttonStyle(.ppPrimary)
        .disabled(!canSubmit || auth.isLoading)
        .opacity(canSubmit || auth.isLoading ? 1 : 0.5)
        .animation(PPMotion.snappy, value: canSubmit)
        .animation(PPMotion.snappy, value: auth.isLoading)
    }

    // MARK: - Mode toggle

    private var modeToggle: some View {
        HStack(spacing: PPSpacing.xs) {
            Text(mode == .login ? "New here?" : "Already have an account?")
                .font(.ppBody)
                .foregroundStyle(Color.ppMuted)
            Button(mode == .login ? "Create one" : "Log in") {
                auth.errorMessage = nil
                mode = mode == .login ? .signup : .login
            }
            .buttonStyle(.ppGhost)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, PPSpacing.sm)
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        switch mode {
        case .login:
            // Login accepts a username or an email, so only require non-empty.
            let identifierOK = !email.trimmingCharacters(in: .whitespaces).isEmpty
            return identifierOK && !password.isEmpty
        case .signup:
            let emailOK = email.contains("@") && email.contains(".")
            return emailOK && password.count >= 8
        }
    }

    private func submit() {
        guard canSubmit, !auth.isLoading else { return }
        let trimmedName = fullName.trimmingCharacters(in: .whitespaces)
        let trimmedRole = targetRole.trimmingCharacters(in: .whitespaces)
        Task {
            switch mode {
            case .login:
                await auth.login(email: email, password: password)
            case .signup:
                await auth.signup(
                    email: email,
                    password: password,
                    fullName: trimmedName.isEmpty ? nil : trimmedName,
                    targetRole: trimmedRole.isEmpty ? nil : trimmedRole
                )
            }
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
}
