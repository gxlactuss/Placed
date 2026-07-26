import Foundation

/// What the student told us before their first mock interview.
struct InterviewSetup: Codable, Equatable {
    /// Compulsory — every round is framed around it.
    var targetRole: String
    /// The model's brief on the resume's projects. Shown to the student; `nil`
    /// when the resume was skipped or held no recognisable projects.
    var projectsSummary: String?
    /// The redacted projects section itself. This is what the interviewer is
    /// actually prompted with — the summary is a lossy paraphrase, and the
    /// projects round needs the real detail to ask about specific decisions.
    var projectsText: String?
    /// The redacted skills section, for the tech-stack round. `nil` when the
    /// resume had no skills heading.
    var skills: String?

    var hasProjects: Bool { !(projectsText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasSkills: Bool { !(skills ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Persists the interview setup per account.
///
/// Keyed by user id for the same reason `SavedQuestionsStore` is: two students
/// sharing a device must not inherit each other's resume summary. Local-only —
/// nothing resume-derived is stored server-side (see the `/resume-summary`
/// route), so this deliberately doesn't sync.
@MainActor
@Observable
final class InterviewSetupStore {

    private(set) var setup: InterviewSetup?

    private let defaults: UserDefaults
    private var userId: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True once the student has been through the setup screen for this account.
    var isComplete: Bool { setup != nil }

    func adopt(userId: Int) {
        guard self.userId != userId else { return }
        self.userId = userId
        setup = load(for: userId)
    }

    func save(_ setup: InterviewSetup) {
        self.setup = setup
        guard let userId, let data = try? JSONEncoder().encode(setup) else { return }
        defaults.set(data, forKey: Self.key(for: userId))
    }

    /// Sends the student back through setup — for the "Redo setup" affordance.
    func reset() {
        setup = nil
        guard let userId else { return }
        defaults.removeObject(forKey: Self.key(for: userId))
    }

    /// Drops the in-memory copy on sign-out. The stored bucket survives, so
    /// signing back in restores the setup rather than asking twice.
    func clear() {
        userId = nil
        setup = nil
    }

    private func load(for userId: Int) -> InterviewSetup? {
        guard let data = defaults.data(forKey: Self.key(for: userId)) else { return nil }
        return try? JSONDecoder().decode(InterviewSetup.self, from: data)
    }

    private static func key(for userId: Int) -> String { "interviewSetup.user.\(userId)" }
}

extension InterviewSetupStore {
    /// In-memory store for previews, so previews never touch real defaults.
    static func preview(_ setup: InterviewSetup? = nil) -> InterviewSetupStore {
        let store = InterviewSetupStore(
            defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        )
        store.adopt(userId: 1)
        if let setup { store.save(setup) }
        return store
    }
}
