import SwiftUI

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
