import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ResumeImporter {

    enum Phase: Equatable {
        case idle
        case reading
        case summarising
        case done(String)
        case noProjects
        case failed(String)

        var isBusy: Bool { self == .reading || self == .summarising }
    }

    private(set) var phase: Phase = .idle
    private(set) var projectsText: String?
    private(set) var skills: String?

    init(restoring setup: InterviewSetup? = nil) {
        guard let setup else { return }
        projectsText = setup.projectsText
        skills = setup.skills
        phase = setup.projectsSummary.map(Phase.done) ?? .noProjects
    }

    var hasResume: Bool { projectsText != nil || skills != nil }

    var setup: InterviewSetup? {
        guard hasResume else { return nil }
        let summary: String? = if case .done(let text) = phase { text } else { nil }
        return InterviewSetup(projectsSummary: summary, projectsText: projectsText, skills: skills)
    }

    func remove() {
        phase = .idle
        projectsText = nil
        skills = nil
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }

    func process(_ url: URL, targetRole: String) async {
        phase = .reading
        do {
            let text = try await ResumeTextExtractor.extractText(from: url)
            let extraction = ResumeParser.extractProjects(from: text)
            projectsText = extraction.foundProjectsSection ? extraction.text : nil
            skills = ResumeParser.extractSkills(from: text)

            phase = .summarising
            let response: ResumeSummaryResponse = try await NetworkManager.shared.request(
                path: "/api/interview/resume-summary",
                method: .post,
                body: ResumeSummaryRequest(
                    targetRole: targetRole.isEmpty ? "Software Engineer" : targetRole,
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

struct ResumeAttachCard: View {

    let importer: ResumeImporter
    let targetRole: String

    @State private var showFileImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            PPCard {
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    switch importer.phase {
                    case .idle:
                        idleRow
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
                            detail: importer.skills == nil
                                ? "We couldn't spot a projects section. You can carry on, or try a different file."
                                : "We couldn't spot a projects section, but picked up your skills for the tech-stack round."
                        )
                    case .failed(let message):
                        noticeRow(icon: "exclamationmark.triangle.fill", title: "Couldn't read that", detail: message)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animation(PPMotion.snappy, value: importer.phase)

            Text("Read on your phone. Only your project descriptions and skills are sent, never your contact details.")
                .font(.ppMicro)
                .foregroundStyle(Color.ppMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .png, .jpeg, .heic],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importer.process(url, targetRole: targetRole) }
            case .failure(let error):
                importer.fail(error.localizedDescription)
            }
        }
    }

    private var idleRow: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            HStack(alignment: .top, spacing: PPSpacing.lg) {
                PPIconTile(systemName: "doc.text", tint: .ppAccent400)
                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    Text("Attach your resume").font(.ppHeadline)
                    Text("PDF or an image. We'll pull out your projects and skills so the interviewer can ask about them.")
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
            if importer.skills != nil {
                Text("Skills found. Unlocks the tech-stack round.")
                    .font(.ppMicro)
                    .foregroundStyle(Color.ppEasy)
            }
            fileActions(primary: "Use a different file")
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
            fileActions(primary: "Try another file")
        }
    }

    private func fileActions(primary: String) -> some View {
        HStack(spacing: PPSpacing.lg) {
            Button(primary) { showFileImporter = true }
                .buttonStyle(.ppInlineLink)
            Button("Remove") { withAnimation(PPMotion.snappy) { importer.remove() } }
                .buttonStyle(.ppInlineLink)
        }
    }
}

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

#Preview("Empty") {
    ResumeAttachCard(importer: ResumeImporter(), targetRole: "Backend Engineer")
        .padding(PPSpacing.xl)
        .foregroundStyle(Color.ppText)
        .ppScreenBackground()
}

#Preview("Attached") {
    ResumeAttachCard(
        importer: ResumeImporter(restoring: InterviewSetup(
            projectsSummary: "PlacementPrep: a SwiftUI + FastAPI prep app with voice mock interviews.",
            projectsText: "PlacementPrep",
            skills: "Swift, Python"
        )),
        targetRole: "iOS Developer"
    )
    .padding(PPSpacing.xl)
    .foregroundStyle(Color.ppText)
    .ppScreenBackground()
}
