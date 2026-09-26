import Foundation

struct InterviewSetup: Codable, Equatable {
    var projectsSummary: String?
    var projectsText: String?
    var skills: String?

    var hasProjects: Bool { !(projectsText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasSkills: Bool { !(skills ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Whose interview a round imitates: a general campus interview, or one company's.
enum InterviewStyle: Codable, Hashable {
    case general
    case company(String)

    var companyName: String? {
        if case .company(let name) = self { return name }
        return nil
    }
}

@MainActor
@Observable
final class InterviewSetupStore {

    private(set) var setup: InterviewSetup?
    /// nil until the user picks one; rounds then follow their target company.
    private(set) var style: InterviewStyle?

    private let defaults: UserDefaults
    private var userId: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func adopt(userId: Int) {
        guard self.userId != userId else { return }
        self.userId = userId
        setup = load(for: userId)
        style = defaults.data(forKey: Self.styleKey(for: userId))
            .flatMap { try? JSONDecoder().decode(InterviewStyle.self, from: $0) }
    }

    func setStyle(_ style: InterviewStyle) {
        self.style = style
        guard let userId, let data = try? JSONEncoder().encode(style) else { return }
        defaults.set(data, forKey: Self.styleKey(for: userId))
    }

    func save(_ setup: InterviewSetup?) {
        guard let setup else { return reset() }
        self.setup = setup
        guard let userId, let data = try? JSONEncoder().encode(setup) else { return }
        defaults.set(data, forKey: Self.key(for: userId))
    }

    func reset() {
        setup = nil
        guard let userId else { return }
        defaults.removeObject(forKey: Self.key(for: userId))
    }

    func clear() {
        userId = nil
        setup = nil
        style = nil
    }

    private func load(for userId: Int) -> InterviewSetup? {
        guard let data = defaults.data(forKey: Self.key(for: userId)) else { return nil }
        return try? JSONDecoder().decode(InterviewSetup.self, from: data)
    }

    private static func key(for userId: Int) -> String { "interviewSetup.user.\(userId)" }
    private static func styleKey(for userId: Int) -> String { "interviewStyle.user.\(userId)" }
}

extension InterviewSetupStore {
    static func preview(_ setup: InterviewSetup? = nil) -> InterviewSetupStore {
        let store = InterviewSetupStore(
            defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        )
        store.adopt(userId: 1)
        if let setup { store.save(setup) }
        return store
    }
}
