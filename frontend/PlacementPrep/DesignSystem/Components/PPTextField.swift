import SwiftUI

/// Labeled text input used on the auth screen. Mirrors `PPSearchField`'s
/// surface-fill-plus-hairline treatment so forms read as the same system, and
/// adds a small caps label above the field and an optional secure-entry toggle.
struct PPTextField: View {

    let label: String
    let placeholder: String
    @Binding var text: String

    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    /// Capitalization for free-text fields (name, role). Ignored for secure and
    /// email fields, which never auto-capitalize (a capital would corrupt a
    /// password, email, or username like "admin").
    var autocapitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    private var effectiveCapitalization: TextInputAutocapitalization {
        (isSecure || keyboard == .emailAddress || textContentType == .username) ? .never : autocapitalization
    }

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text(label).ppSectionLabelStyle()

            HStack(spacing: PPSpacing.md) {
                Group {
                    if isSecure && !isRevealed {
                        SecureField("", text: $text, prompt: prompt)
                    } else {
                        TextField("", text: $text, prompt: prompt)
                    }
                }
                .font(.ppBody)
                .foregroundStyle(Color.ppText)
                .keyboardType(keyboard)
                .textContentType(textContentType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(effectiveCapitalization)
                .submitLabel(submitLabel)
                .focused($isFocused)
                .onSubmit(onSubmit)

                if isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(Color.ppMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PPSpacing.lg)
            .frame(height: PPSize.control)
            .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.md)
                    .strokeBorder(isFocused ? Color.ppAccent : Color.ppBorder, lineWidth: 1)
            }
            .animation(PPMotion.snappy, value: isFocused)
        }
    }

    private var prompt: Text {
        Text(placeholder).foregroundColor(.ppMuted)
    }
}

#Preview("Text fields") {
    @Previewable @State var email = ""
    @Previewable @State var password = "hunter2"

    VStack(spacing: PPSpacing.xl) {
        PPTextField(
            label: "Email",
            placeholder: "you@example.com",
            text: $email,
            keyboard: .emailAddress,
            textContentType: .emailAddress
        )
        PPTextField(
            label: "Password",
            placeholder: "At least 8 characters",
            text: $password,
            isSecure: true,
            textContentType: .password,
            submitLabel: .go
        )
    }
    .padding(PPSpacing.xl)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
