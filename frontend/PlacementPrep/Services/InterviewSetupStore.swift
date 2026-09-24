import Foundation

struct InterviewSetup: Codable, Equatable {
    var projectsSummary: String?
    var projectsText: String?
    var skills: String?

    var hasProjects: Bool { !(projectsText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasSkills: Bool { !(skills ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

@MainActor
@Observable
final class InterviewSetupStore {

    private(set) var setup: InterviewSetup?

    private let defaults: UserDefaults
    private var userId: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func adopt(userId: Int) {
        guard self.userId != userId else { return }
        self.userId = userId
        setup = load(for: userId)
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
    }

    private func load(for userId: Int) -> InterviewSetup? {
        guard let data = defaults.data(forKey: Self.key(for: userId)) else { return nil }
        return try? JSONDecoder().decode(InterviewSetup.self, from: data)
    }

    private static func key(for userId: Int) -> String { "interviewSetup.user.\(userId)" }
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
