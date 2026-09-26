import SwiftUI

/// Changes the company the user is preparing for after onboarding.
struct TargetCompanySheet: View {

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(CompanyBank.self) private var bank
    @Environment(\.dismiss) private var dismiss

    @State private var choice: CompanyPicker.Choice?
    @State private var otherName = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                CompanyPicker(choice: $choice, otherName: $otherName)
                    .padding(PPSpacing.xl)
                    .ppContentColumn()
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .presentationDragIndicator(.visible)
        .onAppear(perform: restore)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: PPSpacing.md) {
            Text("Target company").font(.ppTitle)
            Spacer()
            if auth.currentUser?.targetCompany != nil {
                Button("Clear") { save(nil) }
                    .font(.ppBodyMedium)
                    .foregroundStyle(Color.ppMuted)
                    .disabled(isSaving)
            }
            Button("Save") { save(resolvedName) }
                .font(.ppBodyMedium)
                .foregroundStyle(Color.ppAccent400)
                .disabled(isSaving || choice == nil)
        }
        .padding(.horizontal, PPSpacing.xl)
        .padding(.top, PPSpacing.xl)
        .padding(.bottom, PPSpacing.md)
    }

    private var resolvedName: String? {
        switch choice {
        case .company(let company): return company.name
        case .other:
            let typed = otherName.trimmingCharacters(in: .whitespacesAndNewlines)
            return typed.isEmpty ? nil : typed
        case nil: return nil
        }
    }

    private func restore() {
        guard choice == nil, let saved = auth.currentUser?.targetCompany else { return }
        if let match = bank.company(named: saved) {
            choice = .company(match)
        } else {
            choice = .other
            otherName = saved
        }
    }

    private func save(_ name: String?) {
        isSaving = true
        Task {
            await auth.updateTargetCompany(name)
            isSaving = false
            PPHaptics.success()
            dismiss()
        }
    }
}
