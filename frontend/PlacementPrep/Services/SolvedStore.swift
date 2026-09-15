import Foundation

@MainActor
@Observable
final class SolvedStore {

    private static let defaultsKey = "solvedProblemIDs"
    private static let ownerKey = "solvedProblemsOwner"

    private(set) var solvedIDs: Set<String>
    private let defaults: UserDefaults
    private var userId: Int?
    private let network = NetworkManager.shared

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.solvedIDs = decoded
        } else {
            self.solvedIDs = []
        }
    }

    func isSolved(_ id: DSAProblem.ID) -> Bool {
        solvedIDs.contains(id)
    }

    func toggle(_ id: DSAProblem.ID) {
        let nowSolved: Bool
        if solvedIDs.contains(id) {
            solvedIDs.remove(id)
            nowSolved = false
        } else {
            solvedIDs.insert(id)
            nowSolved = true
        }
        persist()

        guard userId != nil else { return }
        Task {
            if nowSolved {
                try? await network.send(path: "/api/dsa/solved", method: .post, body: SolvedSlugRequest(slug: id))
            } else {
                try? await network.send(path: "/api/dsa/solved/\(id)", method: .delete)
            }
        }
    }

    func sync(userId: Int) async {
        if let owner = defaults.object(forKey: Self.ownerKey) as? Int, owner != userId {
            solvedIDs = []
            persist()
        }
        self.userId = userId
        defaults.set(userId, forKey: Self.ownerKey)

        do {
            let serverSlugs: [String] = try await network.request(path: "/api/dsa/solved")
            var merged = Set(serverSlugs)

            for slug in solvedIDs.subtracting(merged) {
                try? await network.send(path: "/api/dsa/solved", method: .post, body: SolvedSlugRequest(slug: slug))
                merged.insert(slug)
            }

            solvedIDs = merged
            persist()
        } catch {
        }
    }

    func clear() {
        userId = nil
        solvedIDs = []
        persist()
    }

    func solvedCount(in problems: [DSAProblem]) -> Int {
        problems.reduce(into: 0) { total, problem in
            if solvedIDs.contains(problem.id) { total += 1 }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(solvedIDs) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

extension SolvedStore {
    static func preview(solved: Set<String> = []) -> SolvedStore {
        let suiteName = "preview.\(UUID().uuidString)"
        let store = SolvedStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        for id in solved { store.toggle(id) }
        return store
    }
}
