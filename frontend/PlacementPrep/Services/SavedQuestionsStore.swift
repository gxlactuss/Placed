import Foundation

/// Persists which quiz questions the student has bookmarked for later review.
///
/// Keyed by `Question.id` — the same stable id used everywhere else — so a saved
/// question survives re-decoding the quiz JSON and reordering options. Backed by
/// `UserDefaults` like `SolvedStore`: the set is decoded once at launch and only
/// encoded on change.
@MainActor
@Observable
final class SavedQuestionsStore {

    private static let defaultsKey = "savedQuestionIDs"

    private(set) var savedIDs: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.savedIDs = decoded
        } else {
            self.savedIDs = []
        }
    }

    var count: Int { savedIDs.count }

    func isSaved(_ id: String) -> Bool { savedIDs.contains(id) }

    func toggle(_ id: String) {
        if savedIDs.contains(id) {
            savedIDs.remove(id)
        } else {
            savedIDs.insert(id)
        }
        persist()
    }

    func remove(_ id: String) {
        guard savedIDs.contains(id) else { return }
        savedIDs.remove(id)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(savedIDs) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

extension SavedQuestionsStore {
    /// In-memory store for previews, so previews never touch real defaults.
    static func preview(saved: Set<String> = []) -> SavedQuestionsStore {
        let store = SavedQuestionsStore(
            defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        )
        for id in saved { store.toggle(id) }
        return store
    }
}
