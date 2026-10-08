import Testing
@testable import PlacementPrep

@Suite("ResumeParser redaction")
struct ResumeParserTests {

    /// Text with no section headings goes through the plain redact-and-cap path.
    private func redacted(_ text: String) -> String {
        ResumeParser.extractProjects(from: text).text
    }

    private func hasDigits(_ text: String) -> Bool {
        text.contains { $0.isNumber }
    }

    @Test(arguments: [
        "jane.doe@example.com",
        "JANE_DOE+resume@mail.college.ac.in",
        "j.d-99%x@sub.domain.io",
    ])
    func emailsAreRedacted(email: String) {
        let output = redacted("Contact: \(email) today")
        #expect(output == "Contact: [redacted] today")
    }

    // Keep these two lists identical to PHONE_SAMPLES / NOT_PHONE_SAMPLES in
    // backend/tests/test_resume_privacy.py: both sides share one phone regex.
    @Test(arguments: [
        "9876543210",
        "+91 9876543210",
        "+91-9876543210",
        "+91 98765 43210",
        "98765 43210",
        "98765-43210",
        "+919876543210",
        "919876543210",
        "098765 43210",
        "0091 98765 43210",
        "+44 7911123456",
        "+1 5551234567",
        "555-123-4567",
        "555.123.4567",
        "555 123 4567",
        "(555) 123-4567",
        "+1 (555) 123-4567",
    ])
    func phoneNumbersAreRedacted(phone: String) {
        let output = redacted("Phone: \(phone) (mobile)")
        #expect(output == "Phone: [redacted] (mobile)")
        #expect(!hasDigits(output), "Leaked digits in: \(output)")
    }

    @Test(arguments: [
        "2019",
        "2019-2023",
        "2019 - 2023",
        "Jan 2019 – May 2023",
        "CGPA 9.12/10",
        "99.5% uptime",
        "v1.2.3",
        "Mumbai 400001",
        "12/05/2023",
        "2023-05-12",
        "reduced latency by 800ms to 120ms",
        "1,50,000 users",
        "1,200,000 requests/day",
        "Top 1% of 150000 candidates",
        "Roll no. 190123456",
    ])
    func ordinaryNumbersAreNotRedacted(text: String) {
        #expect(redacted(text) == text)
    }

    @Test func ordinaryNumbersAndYearsSurvive() {
        let text = """
        B.Tech Computer Engineering, 2019 - 2023, CGPA 8.92/10
        Ranked 12 of 450 teams at Smart India Hackathon 2022
        Reduced latency by 35% serving 1,200,000 requests/day
        Class XII: 94.6% (2019)
        """
        #expect(redacted(text) == text)
    }

    @Test func mixedContactLineRedactsOnlyContactDetails() {
        let output = redacted("jane@x.com | 9876543210 | Mumbai 400001 | Batch of 2025")
        #expect(output == "[redacted] | [redacted] | Mumbai 400001 | Batch of 2025")
    }

    @Test func extractProjectsFindsSectionAndRedactsIt() {
        let text = """
        Jane Doe
        jane@example.com
        PROJECTS
        Chat app in Swift, contact me at 9876543210
        Built in 2023
        EXPERIENCE
        Intern at Acme
        """
        let extraction = ResumeParser.extractProjects(from: text)
        #expect(extraction.foundProjectsSection)
        #expect(extraction.text == "Chat app in Swift, contact me at [redacted]\nBuilt in 2023")
    }

    @Test func extractSkillsIsRedacted() {
        let text = "Skills:\nSwift, Python, reach me: a@b.co\nEducation\nKJSIT"
        #expect(ResumeParser.extractSkills(from: text) == "Swift, Python, reach me: [redacted]")
        #expect(ResumeParser.extractSkills(from: "no headings here") == nil)
    }

    // MARK: redactForReview

    @Test func redactForReviewRedactsNameOnFirstLine() {
        let text = "Jane Doe\nSoftware Engineer\nEDUCATION\nKJSIT, 2021 - 2025"
        let output = ResumeParser.redactForReview(text)
        #expect(output == "[redacted]\nSoftware Engineer\nEDUCATION\nKJSIT, 2021 - 2025")
    }

    @Test func redactForReviewSkipsLeadingBlankLines() {
        let output = ResumeParser.redactForReview("\n\n   Jane Q Doe  \nMumbai")
        #expect(output.hasPrefix("[redacted]"))
        #expect(!output.contains("Jane"))
    }

    @Test func redactForReviewKeepsFirstLineThatIsNotAName() {
        #expect(ResumeParser.redactForReview("EDUCATION\nKJSIT").hasPrefix("EDUCATION"))
        #expect(ResumeParser.redactForReview("Class of 2025\nKJSIT").hasPrefix("Class of 2025"))
    }

    @Test func redactForReviewRedactsContactsAndLinks() {
        let text = """
        Jane Doe
        jane@example.com | +91 9876543210 | linkedin.com/in/jane-doe | https://github.com/janedoe
        Portfolio: https://janedoe.dev/work?x=1
        Graduated 2024
        """
        let output = ResumeParser.redactForReview(text)
        #expect(!output.contains("jane"))
        #expect(!output.contains("9876543210"))
        #expect(!output.contains("janedoe"))
        #expect(output.contains("Graduated 2024"))
        #expect(output.hasPrefix("[redacted]\n"))
    }

    // MARK: character caps

    @Test func projectsTextIsCappedAt6000Characters() {
        let long = String(repeating: "abcdefghij ", count: 1000)
        #expect(ResumeParser.extractProjects(from: long).text.count == 6000)
    }

    @Test func skillsTextIsCappedAt1200Characters() {
        let long = "Skills\n" + String(repeating: "Swift ", count: 1000)
        #expect(ResumeParser.extractSkills(from: long)?.count == 1200)
    }

    @Test func reviewTextIsCappedAt12000Characters() {
        let long = "EDUCATION\n" + String(repeating: "abcdefghij ", count: 2000)
        #expect(ResumeParser.redactForReview(long).count == 12000)
    }

    @Test func shortTextIsNotPadded() {
        #expect(ResumeParser.extractProjects(from: "  short  ").text == "short")
    }
}
