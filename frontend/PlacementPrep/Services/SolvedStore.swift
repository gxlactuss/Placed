import Foundation

/// Persists which problems the student has solved.
///
/// Backed by `UserDefaults` (the same store `@AppStorage` writes to) rather than
/// `@AppStorage` directly, because the value is a `Set<String>` — `@AppStorage`
/// would need a `RawRepresentable` shim that re-encodes JSON on every read.
/// Here the set is decoded once at launch and only encoded on change.
///
/// Keyed by LeetCode slug, so solving "Two Sum" marks it solved everywhere it
/// appears — it is the same problem, whichever company list you found it in.
@MainActor
@Observable
final class SolvedStore {

    private static let defaultsKey = "solvedProblemIDs"

    private(set) var solvedIDs: Set<String>
    private let defaults: UserDefaults

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
        if solvedIDs.contains(id) {
            solvedIDs.remove(id)
        } else {
            solvedIDs.insert(id)
        }
        persist()
    }

    /// How many of the given problems are solved — drives the per-company and
    /// per-difficulty counters.
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
    /// An in-memory store for previews, so previews never touch real defaults.
    static func preview(solved: Set<String> = []) -> SolvedStore {
        let suiteName = "preview.\(UUID().uuidString)"
        let store = SolvedStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        for id in solved { store.toggle(id) }
        return store
    }
}
