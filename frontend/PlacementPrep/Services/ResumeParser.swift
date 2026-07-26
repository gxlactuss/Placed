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
        "key projects", "selected projects", "project experience", "project work",
        // Research-heavy resumes routinely file projects and papers under one
        // heading. These must stay longer than the bare "publications" in
        // `otherHeadings`, which would otherwise match first and end the block
        // before it started — see `splittingGluedHeadings`, which tries the
        // longest heading first for exactly this reason.
        "projects & publications", "projects and publications",
        "publications & projects", "publications and projects"
    ]

    /// Headings that begin the skills block. Kept separate from `otherHeadings`
    /// so the same scanner can pull either section out.
    private static let skillHeadings = [
        "skills", "technical skills", "technologies", "tech stack",
        "skills and tools", "tools and technologies", "technical proficiencies",
        "programming languages", "languages", "core competencies"
    ]

    private static let otherHeadings = [
        "experience", "work experience", "professional experience", "employment",
        "internship", "internships", "education", "academics",
        "achievements", "accomplishments", "certifications",
        "certificates", "awards", "honors", "honours", "activities",
        "extracurricular", "positions of responsibility", "publications",
        "coursework", "interests", "hobbies", "summary",
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
        let joined = section(under: projectHeadings, in: resumeText)

        // Only fall back when there was genuinely nothing to find. An earlier
        // version required the block to clear a length floor, which quietly
        // demoted a *short but real* projects section into "send the whole
        // resume" — the exact PII leak this type exists to prevent. If the
        // heading was there and anything followed it, that's the answer; the
        // backend's NO_PROJECTS_FOUND sentinel handles genuine junk.
        guard let joined else {
            return Extraction(text: redactAndCap(resumeText), foundProjectsSection: false)
        }
        return Extraction(text: redactAndCap(joined), foundProjectsSection: true)
    }

    /// The skills block, or `nil` when the resume has none.
    ///
    /// Deliberately has **no** whole-document fallback, unlike projects: sending
    /// an entire resume labelled "claimed skills" would produce nonsense
    /// questions, and the tech-stack round already degrades gracefully by asking
    /// the candidate what they're strongest in.
    static func extractSkills(from resumeText: String) -> String? {
        guard let joined = section(under: skillHeadings, in: resumeText) else { return nil }
        // Skills lists are short; a long one means the heading detection ran on
        // past the section, so keep the cap tight.
        return redact(joined, limit: 1200)
    }

    /// Collects the lines under any heading in `startHeadings`, stopping at the
    /// next heading that isn't one of them. Returns `nil` if no such heading
    /// appeared, or nothing followed it.
    private static func section(under startHeadings: [String], in resumeText: String) -> String? {
        let lines = splittingGluedHeadings(
            resumeText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        )

        var collected: [String] = []
        var inSection = false
        var sawHeading = false

        for line in lines {
            guard let heading = headingKey(for: line) else {
                if inSection, !line.isEmpty { collected.append(line) }
                continue
            }
            if startHeadings.contains(heading) {
                // A second heading of the same kind (e.g. "Projects" then
                // "Academic Projects") continues the block rather than
                // restarting it.
                inSection = true
                sawHeading = true
            } else if inSection {
                break  // reached the next unrelated section — done
            }
        }

        let joined = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return sawHeading && !joined.isEmpty ? joined : nil
    }

    /// Every heading we know, longest first.
    ///
    /// The ordering is load-bearing for `splittingGluedHeadings`: "PROJECTS &
    /// PUBLICATIONS" also ends with the shorter "PUBLICATIONS", and matching
    /// that one would split the heading in half and end the projects block
    /// instead of starting it.
    private static let headingsLongestFirst: [String] =
        (projectHeadings + skillHeadings + otherHeadings).sorted { $0.count > $1.count }

    /// Breaks a heading back onto its own line when the extracted text glued it
    /// to the tail of the previous one.
    ///
    /// PDF text layers do this constantly — LaTeX templates that set a section
    /// heading tight against the preceding block emit both in one run, so a
    /// resume with a real projects section reads as having none. Observed on a
    /// real CV as `"…submitted for the COLM 2026 conference. PROJECTS &
    /// PUBLICATIONS"`, which silently cost the student the projects round.
    ///
    /// **Vision OCR does not rescue this** — it sees the heading and the line
    /// above as one visual row and garbles the overlap ("PROJECTS PUBECAT18N"),
    /// so this has to be fixed in the text, not the extractor.
    ///
    /// Requiring the trailing heading to be capitalised in the source is what
    /// stops prose like "shipped two personal projects" being split apart:
    /// headings are typeset in caps, sentences aren't. Only trailing headings
    /// are handled — a heading glued to the *front* of its own content stays
    /// unrecognised, which is the safer failure since it just means the whole
    /// resume is sent instead.
    private static func splittingGluedHeadings(_ lines: [String]) -> [String] {
        var result: [String] = []

        for line in lines {
            // Already a clean heading, or far too long to be one with a tail.
            guard headingKey(for: line) == nil, line.count <= 400 else {
                result.append(line)
                continue
            }

            let upperLine = line.uppercased()
            var split = false

            for heading in headingsLongestFirst {
                let candidate = heading.uppercased()
                guard upperLine.hasSuffix(candidate), line.count > candidate.count else { continue }

                let cut = line.index(line.endIndex, offsetBy: -candidate.count)
                let tail = String(line[cut...])
                let head = String(line[..<cut]).trimmingCharacters(in: .whitespaces)
                // Capitalised in the source, and something real precedes it.
                guard tail == tail.uppercased(), !head.isEmpty else { continue }

                result.append(head)
                result.append(tail)
                split = true
                break
            }

            if !split { result.append(line) }
        }

        return result
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
        let known = projectHeadings.contains(cleaned)
            || skillHeadings.contains(cleaned)
            || otherHeadings.contains(cleaned)
        guard known else { return nil }
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
        redact(text, limit: characterLimit)
    }

    private static func redact(_ text: String, limit: Int) -> String {
        var redacted = text
        for pattern in [emailPattern] + phonePatterns {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: [.regularExpression]
            )
        }
        redacted = redacted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard redacted.count > limit else { return redacted }
        return String(redacted.prefix(limit))
    }
}
