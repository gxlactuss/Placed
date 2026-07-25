import SwiftUI

/// Email verification, shown after sign-up (gated on `currentUser.isVerified`).
/// The user enters the 6-digit code emailed to them; a resend and a log-out
/// escape hatch are provided for a wrong address.
struct VerifyEmailView: View {

    @EnvironmentObject private var auth: AuthViewModel

    @State private var code = ""
    @State private var resendNotice: String?

    private var email: String { auth.currentUser?.email ?? "your email" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.xl) {
                header
                codeField
                banner
                verifyButton
                footer
            }
            .padding(PPSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text("Check your inbox.")
                .font(.ppDisplay)
            (
                Text("We sent a 6-digit code to ")
                    .foregroundStyle(Color.ppMuted)
                + Text(email).foregroundStyle(Color.ppText)
                + Text(". Enter it below to verify your account.")
                    .foregroundStyle(Color.ppMuted)
            )
            .font(.ppBody)
        }
        .padding(.top, PPSpacing.xxl)
        .padding(.bottom, PPSpacing.sm)
    }

    private var codeField: some View {
        PPTextField(
            label: "Verification code",
            placeholder: "123456",
            text: $code,
            keyboard: .numberPad,
            textContentType: .oneTimeCode
        )
        .onChange(of: code) { _, newValue in
            // Keep it to 6 digits.
            let digits = newValue.filter(\.isNumber)
            code = String(digits.prefix(6))
            resendNotice = nil
        }
        #if DEBUG
        // Dev builds use a fixed code (no email is sent), so prefill it and say so.
        .onAppear { if code.isEmpty { code = "123456" } }
        .overlay(alignment: .bottomLeading) {
            Text("Dev build — code is 123456")
                .font(.ppMicro)
                .foregroundStyle(Color.ppMuted)
                .offset(y: 20)
        }
        #endif
    }

    @ViewBuilder
    private var banner: some View {
        if let message = auth.errorMessage {
            noticeRow(icon: "exclamationmark.triangle.fill", tint: .ppHard, text: message)
        } else if let notice = resendNotice {
            noticeRow(icon: "checkmark.circle.fill", tint: .ppAccent400, text: notice)
        }
    }

    private func noticeRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: PPSpacing.sm) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .font(.ppCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PPSpacing.md)
        .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: PPRadius.md)
                .strokeBorder(tint.opacity(0.4), lineWidth: 1)
        }
    }

    private var verifyButton: some View {
        Button(action: verify) {
            if auth.isLoading {
                ProgressView().tint(.ppOnAccent)
            } else {
                Text("Verify")
            }
        }
        .buttonStyle(.ppPrimary)
        .disabled(code.count != 6 || auth.isLoading)
        .opacity(code.count == 6 || auth.isLoading ? 1 : 0.5)
        .animation(PPMotion.snappy, value: code.count)
    }

    private var footer: some View {
        VStack(spacing: PPSpacing.md) {
            HStack(spacing: PPSpacing.sm) {
                Text("Didn't get it?")
                    .font(.ppBody)
                    .foregroundStyle(Color.ppMuted)
                Button("Resend code") {
                    Task {
                        await auth.resendVerification()
                        if auth.errorMessage == nil { resendNotice = "New code sent." }
                    }
                }
                .buttonStyle(.ppInlineLink)
            }

            Button("Use a different email") { auth.logout() }
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, PPSpacing.sm)
    }

    private func verify() {
        guard code.count == 6, !auth.isLoading else { return }
        Task { await auth.verifyEmail(code: code) }
    }
}

#Preview {
    VerifyEmailView()
        .environmentObject(AuthViewModel())
}
