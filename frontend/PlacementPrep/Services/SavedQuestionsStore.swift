import Foundation

@MainActor
@Observable
final class SavedQuestionsStore {
    private static let legacyKey = "savedQuestionIDs"

    private(set) var savedIDs: Set<String>
    private let defaults: UserDefaults
    private var userId: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.savedIDs = Self.load(from: defaults, key: Self.key(for: nil))
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

    func adopt(userId: Int) {
        guard self.userId != userId else { return }
        self.userId = userId
        migrateLegacyBucket(to: userId)
        savedIDs = Self.load(from: defaults, key: Self.key(for: userId))
    }

    func clear() {
        userId = nil
        savedIDs = Self.load(from: defaults, key: Self.key(for: nil))
    }

    private func migrateLegacyBucket(to userId: Int) {
        guard let data = defaults.data(forKey: Self.legacyKey) else { return }
        defaults.removeObject(forKey: Self.legacyKey)
        guard let legacy = try? JSONDecoder().decode(Set<String>.self, from: data),
              !legacy.isEmpty else { return }
        let key = Self.key(for: userId)
        Self.save(legacy.union(Self.load(from: defaults, key: key)), to: defaults, key: key)
    }

    private static func key(for userId: Int?) -> String {
        userId.map { "savedQuestionIDs.user.\($0)" } ?? "savedQuestionIDs.signedOut"
    }

    private static func load(from defaults: UserDefaults, key: String) -> Set<String> {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return decoded
    }

    private static func save(_ ids: Set<String>, to defaults: UserDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        defaults.set(data, forKey: key)
    }

    private func persist() {
        Self.save(savedIDs, to: defaults, key: Self.key(for: userId))
    }
}

extension SavedQuestionsStore {
    static func preview(saved: Set<String> = []) -> SavedQuestionsStore {
        let store = SavedQuestionsStore(
            defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        )
        for id in saved { store.toggle(id) }
        return store
    }
}
