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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.xl) {
                brand
                fields
                errorBanner
                primaryButton
                socialSection
                modeToggle
            }
            .padding(PPSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ppContentColumn()
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
                label: mode == .signup ? "Email" : "Email or username",
                placeholder: "you@example.com",
                text: $email,
                keyboard: mode == .signup ? .emailAddress : .default,
                textContentType: mode == .signup ? .emailAddress : .username
            )

            PPTextField(
                label: "Password",
                placeholder: mode == .signup ? "At least 8 characters" : "Your password",
                text: $password,
                isSecure: true,
                textContentType: mode == .signup ? .newPassword : .password,
                submitLabel: .go,
                onSubmit: submit
            )

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

    // MARK: - Social sign-in

    private var socialSection: some View {
        VStack(spacing: PPSpacing.md) {
            HStack(spacing: PPSpacing.md) {
                dividerLine
                Text("or")
                    .font(.ppCaption)
                    .foregroundStyle(Color.ppMuted)
                dividerLine
            }

            Button {
                Task { await auth.signInWithOAuth("google") }
            } label: {
                Label {
                    Text("Continue with Google")
                } icon: {
                    PPBrandMark(provider: .google)
                }
            }
            .buttonStyle(.ppSecondary)

            Button {
                Task { await auth.signInWithOAuth("github") }
            } label: {
                Label {
                    Text("Continue with GitHub")
                } icon: {
                    PPBrandMark(provider: .github)
                }
            }
            .buttonStyle(.ppSecondary)
        }
        .disabled(auth.isLoading)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.ppBorder)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Mode toggle

    private var modeToggle: some View {
        HStack(spacing: PPSpacing.sm) {
            Text(mode == .login ? "New here?" : "Already have an account?")
                .font(.ppBody)
                .foregroundStyle(Color.ppMuted)
            Button(mode == .login ? "Create one" : "Log in") {
                auth.errorMessage = nil
                mode = mode == .login ? .signup : .login
            }
            .buttonStyle(.ppInlineLink)
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
        Task {
            switch mode {
            case .login:
                await auth.login(email: email, password: password)
            case .signup:
                await auth.signup(
                    email: email,
                    password: password,
                    fullName: trimmedName.isEmpty ? nil : trimmedName,
                    // Collected on the very next screen, from a fixed list.
                    // A role must be one of the known ones or the technical
                    // round and the role-locked quiz have nothing to key on.
                    targetRole: nil
                )
            }
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
}
