import Foundation

enum ResumeParser {
    private static let projectHeadings = [
        "projects", "project", "personal projects", "academic projects",
        "key projects", "selected projects", "project experience", "project work",
        "projects & publications", "projects and publications",
        "publications & projects", "publications and projects"
    ]

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

    struct Extraction {
        let text: String
        let foundProjectsSection: Bool
    }

    private static let characterLimit = 6000

    static func extractProjects(from resumeText: String) -> Extraction {
        let joined = section(under: projectHeadings, in: resumeText)

        guard let joined else {
            return Extraction(text: redactAndCap(resumeText), foundProjectsSection: false)
        }
        return Extraction(text: redactAndCap(joined), foundProjectsSection: true)
    }

    static func extractSkills(from resumeText: String) -> String? {
        guard let joined = section(under: skillHeadings, in: resumeText) else { return nil }
        return redact(joined, limit: 1200)
    }

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
                inSection = true
                sawHeading = true
            } else if inSection {
                break
            }
        }

        let joined = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return sawHeading && !joined.isEmpty ? joined : nil
    }

    private static let headingsLongestFirst: [String] =
        (projectHeadings + skillHeadings + otherHeadings).sorted { $0.count > $1.count }

    private static func splittingGluedHeadings(_ lines: [String]) -> [String] {
        var result: [String] = []

        for line in lines {
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

    private static let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
    private static let phonePatterns = [
        #"(?:\+\d{1,3}[\s-]?)?\b\d{10}\b"#,
        #"\b\d{3}[\s.-]\d{3}[\s.-]\d{4}\b"#
    ]

    private static let profileLinkPattern =
        #"(?i)\b(?:https?://)?(?:www\.)?(?:linkedin\.com|github\.com|gitlab\.com|leetcode\.com|behance\.net)/\S*"#
    private static let urlPattern = #"(?i)\bhttps?://\S+"#
    private static let reviewCharacterLimit = 12000

    static func deviceSignals(for document: ResumeTextExtractor.Document) -> ResumeDeviceSignals {
        let text = document.text
        func contains(_ pattern: String) -> Bool {
            text.range(of: pattern, options: .regularExpression) != nil
        }
        return ResumeDeviceSignals(
            hasEmail: contains(emailPattern),
            hasPhone: phonePatterns.contains(where: contains),
            hasLinks: contains(profileLinkPattern)
                || text.localizedCaseInsensitiveContains("linkedin")
                || text.localizedCaseInsensitiveContains("github"),
            pageCount: max(document.pageCount, 1),
            hasTextLayer: document.hasTextLayer
        )
    }

    static func redactForReview(_ resumeText: String) -> String {
        var text = resumeText
        for pattern in [profileLinkPattern, urlPattern] {
            text = text.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }

        var lines = text.components(separatedBy: .newlines)
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           looksLikeName(lines[first]) {
            lines[first] = "[redacted]"
        }
        return redact(lines.joined(separator: "\n"), limit: reviewCharacterLimit)
    }

    private static func looksLikeName(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let words = trimmed.split(separator: " ")
        return (1...5).contains(words.count)
            && trimmed.count <= 40
            && trimmed.rangeOfCharacter(from: .decimalDigits) == nil
            && !trimmed.contains("@")
            && headingKey(for: trimmed) == nil
    }

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
