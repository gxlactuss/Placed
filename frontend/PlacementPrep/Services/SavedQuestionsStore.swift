import Foundation

/// Persists which quiz questions the student has bookmarked for later review.
///
/// Keyed by `Question.id` — the same stable id used everywhere else — so a saved
/// question survives re-decoding the quiz JSON and reordering options. Backed by
/// `UserDefaults` like `SolvedStore`: the set is decoded once at launch and only
/// encoded on change.
///
/// **Scoped per account.** Bookmarks are the one piece of progress with no
/// server table behind them, so unlike `SolvedStore` there's nothing to
/// reconcile against — instead each user gets their own defaults bucket on the
/// device. That keeps one account's saves out of another's (they used to share a
/// single key, so every account saw everyone's bookmarks) while still letting a
/// user sign out and back in without losing them. The trade-off of staying
/// device-local: bookmarks don't follow the account to another device.
@MainActor
@Observable
final class SavedQuestionsStore {

    /// The pre-scoping key: one bucket shared by every account on the device.
    /// Handed to the first account that signs in, then retired.
    private static let legacyKey = "savedQuestionIDs"

    private(set) var savedIDs: Set<String>
    private let defaults: UserDefaults
    /// Whose bookmarks are loaded. `nil` before sign-in — saves made then land in
    /// their own bucket rather than leaking into the next account.
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

    // MARK: - Account scoping

    /// Loads `userId`'s bookmarks. Called wherever the other stores call
    /// `sync(userId:)`; it isn't named `sync` because there's no server side to
    /// reconcile — switching accounts just swaps which bucket is in memory.
    func adopt(userId: Int) {
        guard self.userId != userId else { return }
        self.userId = userId
        migrateLegacyBucket(to: userId)
        savedIDs = Self.load(from: defaults, key: Self.key(for: userId))
    }

    /// Drops the signed-in user's bookmarks from memory on sign-out. Their bucket
    /// is deliberately left on disk, so signing back in restores them — note this
    /// must not `persist()`, which would write the empty set over their saves.
    func clear() {
        userId = nil
        savedIDs = Self.load(from: defaults, key: Self.key(for: nil))
    }

    /// Bookmarks saved before scoping existed sit in one shared bucket — the bug
    /// this fixes. Fold them into the first account that signs in, then remove
    /// the key so no later account inherits them too.
    private func migrateLegacyBucket(to userId: Int) {
        guard let data = defaults.data(forKey: Self.legacyKey) else { return }
        defaults.removeObject(forKey: Self.legacyKey)
        guard let legacy = try? JSONDecoder().decode(Set<String>.self, from: data),
              !legacy.isEmpty else { return }
        let key = Self.key(for: userId)
        Self.save(legacy.union(Self.load(from: defaults, key: key)), to: defaults, key: key)
    }

    // MARK: - Storage

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
    /// In-memory store for previews, so previews never touch real defaults.
    static func preview(saved: Set<String> = []) -> SavedQuestionsStore {
        let store = SavedQuestionsStore(
            defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        )
        for id in saved { store.toggle(id) }
        return store
    }
}
