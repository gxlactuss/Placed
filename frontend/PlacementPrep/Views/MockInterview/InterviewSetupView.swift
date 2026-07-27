import SwiftUI
import UniformTypeIdentifiers

/// Shown once per account, before the first mock interview.
///
/// Collects the target role (compulsory) and, optionally, a resume. The resume
/// never leaves the device as a file: `ResumeTextExtractor` reads it with Vision
/// on-device, `ResumeParser` narrows it to the projects section and strips
/// contact details, and only that text goes to the backend — as a single Gemini
/// call, because the free tier allows just five a minute.
struct InterviewSetupView: View {

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(InterviewSetupStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Picked, not typed — same list as onboarding, so the account's role and
    /// the interview's role can never be two spellings of one job.
    @State private var role: CareerRole?
    @State private var phase: Phase = .idle
    @State private var showFileImporter = false
    /// Held from the on-device parse so `finish()` can persist them — the rounds
    /// are prompted with these, not with the model's summary.
    @State private var projectsText: String?
    @State private var skills: String?

    /// Where the resume half of the screen has got to. The role field stays
    /// live throughout — only the resume work has stages.
    private enum Phase: Equatable {
        case idle
        case reading            // Vision OCR, on-device
        case summarising        // the one Gemini call
        case done(String)       // summary text
        case noProjects         // read fine, but found no projects section
        case failed(String)

        var isBusy: Bool { self == .reading || self == .summarising }
    }

    private var canStart: Bool {
        role != nil && !phase.isBusy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.xl) {
                heading
                roleField
                resumeSection
                Spacer(minLength: PPSpacing.lg)
                startButton
            }
            .padding(PPSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
        .onAppear {
            // Prefill from the account so the common case is one tap.
            if role == nil {
                role = CareerRole(title: store.setup?.targetRole)
                    ?? CareerRole(title: auth.currentUser?.targetRole)
            }
            // Reopened to change something — carry the existing resume forward.
            // These are `@State`, so without this a student who came back only
            // to fix their role would save nil over a resume that was fine and
            // silently re-lock the rounds it had unlocked.
            if case .idle = phase, let saved = store.setup, saved.hasProjects {
                projectsText = saved.projectsText
                skills = saved.skills
                if let summary = saved.projectsSummary { phase = .done(summary) }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .png, .jpeg, .heic],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { processResume(at: url) }
            case .failure(let error):
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Sections

    private var heading: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text("Before we start").font(.ppDisplay)
            Text("Two things, then you're straight into the interview.")
                .font(.ppBody)
                .foregroundStyle(Color.ppMuted)
        }
        .padding(.top, PPSpacing.lg)
    }

    private var roleField: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text("Role you're preparing for").ppSectionLabelStyle()
            Text("Required — every question is framed around this, and the technical round goes deep on it.")
                .font(.ppMicro)
                .foregroundStyle(Color.ppMuted)
                .fixedSize(horizontal: false, vertical: true)
            RolePicker(selection: $role)
                .padding(.top, PPSpacing.xs)
        }
    }

    private var resumeSection: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPSectionHeader("Resume (optional)")

            PPCard {
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    switch phase {
                    case .idle:
                        idleResume
                    case .reading:
                        busyRow("Reading your resume on this device…")
                    case .summarising:
                        busyRow("Summarising your projects…")
                    case .done(let summary):
                        summaryRow(summary)
                    case .noProjects:
                        noticeRow(
                            icon: "questionmark.folder",
                            title: "No projects found",
                            detail: "We couldn't spot a projects section. You can start anyway, or try a different file."
                        )
                    case .failed(let message):
                        noticeRow(icon: "exclamationmark.triangle.fill", title: "Couldn't read that", detail: message)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if case .idle = phase {
                Text("Read on your phone — only your project descriptions are sent, never your contact details.")
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var idleResume: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            HStack(alignment: .top, spacing: PPSpacing.lg) {
                PPIconTile(systemName: "doc.text", tint: .ppAccent400)
                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    Text("Upload your resume").font(.ppHeadline)
                    Text("PDF or an image. We'll pull out your projects so the interviewer can ask about them.")
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button("Choose file") { showFileImporter = true }
                .buttonStyle(.ppSecondary)
        }
    }

    private func busyRow(_ label: String) -> some View {
        HStack(spacing: PPSpacing.lg) {
            ProgressView().tint(Color.ppAccent400)
            Text(label)
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
            Spacer(minLength: 0)
        }
    }

    private func summaryRow(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            HStack(spacing: PPSpacing.sm) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ppEasy)
                Text("Projects picked up").font(.ppHeadline)
                Spacer(minLength: 0)
            }
            Text(summary)
                .font(.ppCaption)
                .foregroundStyle(Color.ppMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let skills, !skills.isEmpty {
                Text("Skills found — unlocks the tech-stack round.")
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppEasy)
            }

            Button("Use a different file") { showFileImporter = true }
                .buttonStyle(.ppInlineLink)
        }
    }

    private func noticeRow(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            HStack(alignment: .top, spacing: PPSpacing.sm) {
                Image(systemName: icon).foregroundStyle(Color.ppAccent400)
                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    Text(title).font(.ppHeadline)
                    Text(detail)
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button("Try another file") { showFileImporter = true }
                .buttonStyle(.ppInlineLink)
        }
    }

    private var startButton: some View {
        VStack(spacing: PPSpacing.sm) {
            Button(action: finish) {
                Text(phase.isBusy ? "Working…" : "Start interview")
            }
            .buttonStyle(.ppPrimary)
            .disabled(!canStart)
            .opacity(canStart ? 1 : 0.5)
            .animation(PPMotion.snappy, value: canStart)

            if case .idle = phase {
                Text("Skipping the resume is fine — you'll still get a full interview.")
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppMuted)
            }
        }
    }

    // MARK: - Work

    /// On-device read → narrow to projects → one Gemini call.
    private func processResume(at url: URL) {
        phase = .reading
        Task {
            do {
                let text = try await ResumeTextExtractor.extractText(from: url)
                let extraction = ResumeParser.extractProjects(from: text)
                // Keep the extracted material: the projects round needs the real
                // text, and the tech-stack round needs the skills list. Only the
                // projects half is sent for summarising.
                projectsText = extraction.foundProjectsSection ? extraction.text : nil
                skills = ResumeParser.extractSkills(from: text)

                phase = .summarising
                let trimmedRole = role?.title ?? ""
                let response: ResumeSummaryResponse = try await NetworkManager.shared.request(
                    path: "/api/interview/resume-summary",
                    method: .post,
                    body: ResumeSummaryRequest(
                        targetRole: trimmedRole.isEmpty ? "Software Engineer" : trimmedRole,
                        projectsText: extraction.text
                    )
                )
                phase = response.noProjectsFound ? .noProjects : .done(response.summary)
            } catch let error as ResumeTextExtractor.ExtractionError {
                phase = .failed(error.localizedDescription)
            } catch {
                phase = .failed("Couldn't summarise that resume. Check your connection and try again.")
            }
        }
    }

    private func finish() {
        guard let role else { return }
        let trimmedRole = role.title

        let summary: String? = if case .done(let text) = phase { text } else { nil }
        store.save(InterviewSetup(
            targetRole: trimmedRole,
            projectsSummary: summary,
            projectsText: projectsText,
            skills: skills
        ))

        // Keep the account's role in step, so Home's greeting and the interview
        // don't disagree about what the student is preparing for.
        if trimmedRole != auth.currentUser?.targetRole {
            Task { await auth.updateTargetRole(trimmedRole) }
        }
        dismiss()
    }
}

// MARK: - Wire types

struct ResumeSummaryRequest: Encodable {
    let targetRole: String
    let projectsText: String

    enum CodingKeys: String, CodingKey {
        case targetRole = "target_role"
        case projectsText = "projects_text"
    }
}

struct ResumeSummaryResponse: Decodable {
    let summary: String
    let noProjectsFound: Bool

    enum CodingKeys: String, CodingKey {
        case summary
        case noProjectsFound = "no_projects_found"
    }
}

#Preview {
    InterviewSetupView()
        .environment(InterviewSetupStore.preview())
        .environmentObject(AuthViewModel())
}
