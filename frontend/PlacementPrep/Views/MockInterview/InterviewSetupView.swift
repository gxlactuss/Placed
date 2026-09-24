import SwiftUI

struct InterviewSetupView: View {

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(InterviewSetupStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var role: CareerRole?
    @State private var resume = ResumeImporter()

    private var canSave: Bool {
        role != nil && !resume.phase.isBusy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.xl) {
                heading
                resumeSection
                roleField
                Spacer(minLength: PPSpacing.lg)
                saveButton
            }
            .padding(PPSpacing.xl)
            .ppContentColumn()
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .onAppear {
            if role == nil { role = CareerRole(title: auth.currentUser?.targetRole) }
            if !resume.hasResume, let saved = store.setup {
                resume = ResumeImporter(restoring: saved)
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Text("Interview profile").font(.ppDisplay)
                Text("Every round uses this. Change it whenever your resume or target role changes.")
                    .font(.ppBody)
                    .foregroundStyle(Color.ppMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: PPSpacing.sm)
            PPIconButton(systemName: "xmark", diameter: 36) { dismiss() }
        }
        .padding(.top, PPSpacing.lg)
    }

    private var resumeSection: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPSectionHeader("Resume")
            ResumeAttachCard(importer: resume, targetRole: role?.title ?? "")
        }
    }

    private var roleField: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text("Role you're preparing for").ppSectionLabelStyle()
            RolePicker(selection: $role)
                .padding(.top, PPSpacing.xs)
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(resume.phase.isBusy ? "Working…" : "Save")
        }
        .buttonStyle(.ppPrimary)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
        .animation(PPMotion.snappy, value: canSave)
    }

    private func save() {
        guard let role else { return }
        store.save(resume.setup)
        if role.title != auth.currentUser?.targetRole {
            Task { await auth.updateTargetRole(role.title) }
        }
        dismiss()
    }
}

#Preview {
    InterviewSetupView()
        .environment(InterviewSetupStore.preview())
        .environmentObject(AuthViewModel())
}
