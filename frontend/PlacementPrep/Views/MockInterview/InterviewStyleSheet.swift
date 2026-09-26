import SwiftUI

/// Picks whose interview the rounds imitate: a general campus interview, or one company's.
struct InterviewStyleSheet: View {

    let current: DSACompany?
    let onPick: (InterviewStyle) -> Void

    @Environment(CompanyBank.self) private var bank
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = [
        GridItem(.flexible(), spacing: PPSpacing.md),
        GridItem(.flexible(), spacing: PPSpacing.md)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: PPSpacing.lg) {
                    Text("HR asks about the company's values, DSA uses the problems it asks most, and the other rounds are pitched at its bar.")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    PPSearchField(placeholder: "Search companies", text: $query)

                    LazyVGrid(columns: columns, spacing: PPSpacing.md) {
                        if query.trimmingCharacters(in: .whitespaces).isEmpty {
                            tile(title: "General", isSelected: current == nil) {
                                Image(systemName: "building.2")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.ppMuted)
                                    .frame(width: 28, height: 28)
                            } action: {
                                pick(.general)
                            }
                        }
                        ForEach(filtered) { company in
                            tile(title: company.name, isSelected: company == current) {
                                PPCompanyLogo(companyName: company.name, size: 28)
                            } action: {
                                pick(.company(company.name))
                            }
                        }
                    }
                }
                .padding(PPSpacing.xl)
                .ppContentColumn()
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Interview style").font(.ppTitle)
            Spacer()
            Button("Done") { dismiss() }
                .font(.ppBodyMedium)
                .foregroundStyle(Color.ppAccent400)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.xl)
        .padding(.bottom, PPSpacing.md)
    }

    private var filtered: [DSACompany] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return bank.companies }
        return bank.companies.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private func tile<Icon: View>(
        title: String,
        isSelected: Bool,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: PPSpacing.sm) {
                icon()
                Text(title)
                    .font(.ppBodyMedium)
                    .foregroundStyle(Color.ppText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppAccent400)
                }
            }
            .padding(PPSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(Color.ppSurface, in: .rect(cornerRadius: PPRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: PPRadius.lg)
                    .strokeBorder(isSelected ? Color.ppAccent400 : Color.ppBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.ppPressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func pick(_ style: InterviewStyle) {
        PPHaptics.light()
        onPick(style)
        dismiss()
    }
}

#Preview {
    InterviewStyleSheet(current: nil, onPick: { _ in })
        .environment(CompanyBank())
}
