import SwiftUI

/// Search input on the Companies screen. Shows a clear button once text is entered.
struct PPSearchField: View {

    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: PPSpacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.ppMuted)

            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundColor(.ppMuted)
            )
            .font(.ppBody)
            .foregroundStyle(Color.ppText)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.ppMuted)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, PPSpacing.lg)
        .frame(height: 48)
        .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: PPRadius.md)
                .strokeBorder(Color.ppBorder, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
    }
}

#Preview("Search field") {
    @Previewable @State var empty = ""
    @Previewable @State var filled = "Two Sum"

    VStack(spacing: PPSpacing.lg) {
        PPSearchField(placeholder: "Search problems or companies", text: $empty)
        PPSearchField(placeholder: "Search problems or companies", text: $filled)
    }
    .padding(PPSpacing.xl)
    .frame(maxHeight: .infinity, alignment: .top)
    .ppScreenBackground()
}
