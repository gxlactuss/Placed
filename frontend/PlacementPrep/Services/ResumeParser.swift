import Foundation

/// Narrows raw resume text down to the part the interviewer actually needs.
///
/// Two jobs, both done before anything is sent: isolate the projects section,
/// and strip the contact details. See `ResumeTextExtractor` for why that matters
/// — on the free Gemini tier, whatever we send is training data a human may read.
enum ResumeParser {

    /// Sections a resume commonly uses. Hitting any of these ends the projects
    /// block; `projects` starts it.
    private static let projectHeadings = [
        "projects", "project", "personal projects", "academic projects",
        "key projects", "selected projects", "project experience", "project work"
    ]

    private static let otherHeadings = [
        "experience", "work experience", "professional experience", "employment",
        "internship", "internships", "education", "academics", "skills",
        "technical skills", "achievements", "accomplishments", "certifications",
        "certificates", "awards", "honors", "honours", "activities",
        "extracurricular", "positions of responsibility", "publications",
        "coursework", "languages", "interests", "hobbies", "summary",
        "objective", "profile", "references", "volunteer", "leadership"
    ]

    /// The result of narrowing: what to send, and whether we actually found a
    /// projects section or fell back to the whole document.
    struct Extraction {
        let text: String
        let foundProjectsSection: Bool
    }

    /// Keeps the payload small and inside the endpoint's 8k ceiling.
    private static let characterLimit = 6000

    static func extractProjects(from resumeText: String) -> Extraction {
        let lines = resumeText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var collected: [String] = []
        var inProjects = false
        var sawProjectsHeading = false

        for line in lines {
            guard let heading = headingKey(for: line) else {
                if inProjects, !line.isEmpty { collected.append(line) }
                continue
            }
            if projectHeadings.contains(heading) {
                // A second projects heading (e.g. "Projects" then "Academic
                // Projects") continues the same block rather than restarting it.
                inProjects = true
                sawProjectsHeading = true
            } else if inProjects {
                break  // reached the next unrelated section — done
            }
        }

        let joined = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // Only fall back when there was genuinely nothing to find. An earlier
        // version required the block to clear a length floor, which quietly
        // demoted a *short but real* projects section into "send the whole
        // resume" — the exact PII leak this type exists to prevent. If the
        // heading was there and anything followed it, that's the answer; the
        // backend's NO_PROJECTS_FOUND sentinel handles genuine junk.
        guard sawProjectsHeading, !joined.isEmpty else {
            return Extraction(text: redactAndCap(resumeText), foundProjectsSection: false)
        }
        return Extraction(text: redactAndCap(joined), foundProjectsSection: true)
    }

    /// Returns the normalised heading if `line` looks like a section heading.
    ///
    /// Headings are short and sit alone on a line, so length is the main guard
    /// against matching a sentence that merely mentions "projects".
    private static func headingKey(for line: String) -> String? {
        let cleaned = line
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t:•·-–—_*#|"))
            .lowercased()
        guard !cleaned.isEmpty, cleaned.count <= 40 else { return nil }
        guard projectHeadings.contains(cleaned) || otherHeadings.contains(cleaned) else { return nil }
        return cleaned
    }

    // MARK: - Redaction

    // Emails and phone numbers are the identifying fields that survive into a
    // projects section (footers, "contact me" lines). URLs are deliberately kept
    // — a GitHub link is genuine project context, and the model uses it.
    private static let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
    // Kept narrow on purpose. A looser pattern (any 6+ digit run) also eats the
    // numbers that make a project worth discussing — "handled 1200000 requests"
    // — so this only matches shapes that are actually phone-like: an optional
    // country code plus ten digits, or a separated 3-3-4 grouping.
    private static let phonePatterns = [
        #"(?:\+\d{1,3}[\s-]?)?\b\d{10}\b"#,
        #"\b\d{3}[\s.-]\d{3}[\s.-]\d{4}\b"#
    ]

    private static func redactAndCap(_ text: String) -> String {
        var redacted = text
        for pattern in [emailPattern] + phonePatterns {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: [.regularExpression]
            )
        }
        redacted = redacted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard redacted.count > characterLimit else { return redacted }
        return String(redacted.prefix(characterLimit))
    }
}
