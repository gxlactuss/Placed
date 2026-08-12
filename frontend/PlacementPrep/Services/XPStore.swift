import Foundation

/// The XP balance and the tier it puts the student in.
///
/// Two things are persisted: the running `total`, and a **ledger** of the
/// award keys already paid. The ledger is what makes every call site safe to
/// call repeatedly — `award(_:)` is a no-op for a key it has seen, so ticking a
/// problem solved, un-ticking it and ticking it again pays once, retaking a
/// cleared quiz pays nothing, and the three places that record daily activity
/// can all try to pay the day's +10 without anyone counting.
///
/// The total is stored rather than recomputed from the ledger because the
/// per-award amounts are a product decision that may change: someone who earned
/// 15 XP for a hard problem keeps it even if that rate is later cut.
///
/// **Scoped per account, device-local** — same shape as `SavedQuestionsStore`
/// and `StreakStore`. There is no XP table on the server yet, so the balance
/// doesn't follow the account to another device. When one lands, this store is
/// the single place that has to learn to sync.
@MainActor
@Observable
final class XPStore {

    private(set) var total: Int
    /// Award keys already paid — see `XPAward.ledgerKey`.
    private(set) var ledger: Set<String>
    /// The most recent award, for the "+15 XP" flash on screen. Not persisted.
    private(set) var lastAward: XPAward?
    /// Set when an award crossed a tier boundary, so the UI can celebrate and
    /// the icon can change. The view clears it once it has been shown.
    var pendingLevelUp: XPLevel?

    private let defaults: UserDefaults
    /// Whose balance is loaded. `nil` before sign-in.
    private var userId: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Open the last signed-in user's bucket, not the signed-out one. On an
        // offline relaunch the tabs appear before `/me` resolves, so without
        // this the XP earned in that window would be paid into a bucket the
        // account never sees again.
        let owner = defaults.object(forKey: Self.lastOwnerKey) as? Int
        let key = Self.key(for: owner)
        self.userId = owner
        self.total = defaults.integer(forKey: Self.totalKey(key))
        self.ledger = Self.loadLedger(from: defaults, key: Self.ledgerKey(key))
    }

    // MARK: - Earning

    /// Pays `award` unless its key has already been paid.
    ///
    /// Returns the points actually paid — **0 for a repeat**. Callers that want
    /// to report "+15 XP" for what just happened must use this rather than the
    /// award's own `points`, or a retake of a cleared quiz would claim XP the
    /// student didn't get.
    @discardableResult
    func award(_ award: XPAward) -> Int {
        guard !ledger.contains(award.ledgerKey) else { return 0 }

        let before = level
        ledger.insert(award.ledgerKey)
        total += award.points
        lastAward = award
        if level > before { pendingLevelUp = level }
        persist()
        return award.points
    }

    /// The day's +10 for practising at all. Idempotent per calendar day, so
    /// every activity that counts as practice can call it.
    @discardableResult
    func awardStreakDay(on date: Date = Date()) -> Int {
        award(.streakDay(Self.dayKey(for: date)))
    }

    func hasAwarded(_ award: XPAward) -> Bool { ledger.contains(award.ledgerKey) }

    // MARK: - Level

    var level: XPLevel { XPLevel.level(for: total) }

    var nextLevel: XPLevel? { level.next }

    /// XP earned inside the current tier, and the size of that tier — the two
    /// numbers behind "30 / 50 to Screened".
    var xpIntoLevel: Int { total - level.minimumXP }

    var xpForLevel: Int? {
        guard let next = nextLevel else { return nil }
        return next.minimumXP - level.minimumXP
    }

    var xpToNextLevel: Int? {
        guard let next = nextLevel else { return nil }
        return max(0, next.minimumXP - total)
    }

    /// 0–1 through the current tier. The top tier is open-ended, so it reads
    /// full rather than never filling.
    var progressInLevel: Double {
        guard let span = xpForLevel, span > 0 else { return 1 }
        return min(1, Double(xpIntoLevel) / Double(span))
    }

    /// Every tier the balance has reached — what the icon picker offers.
    var unlockedLevels: [XPLevel] { XPLevel.allCases.filter { total >= $0.minimumXP } }

    func isUnlocked(_ level: XPLevel) -> Bool { total >= level.minimumXP }

    // MARK: - Account scoping

    /// Loads `userId`'s balance. Called where the other stores sync; there is no
    /// server side to reconcile, so this just swaps which bucket is in memory.
    func adopt(userId: Int) {
        guard self.userId != userId else { return }
        self.userId = userId
        defaults.set(userId, forKey: Self.lastOwnerKey)
        let key = Self.key(for: userId)
        total = defaults.integer(forKey: Self.totalKey(key))
        ledger = Self.loadLedger(from: defaults, key: Self.ledgerKey(key))
        lastAward = nil
        pendingLevelUp = nil
    }

    /// Drops the balance from memory on sign-out. The bucket stays on disk so
    /// signing back in restores it — so this must not `persist()`.
    func clear() {
        userId = nil
        // Forget the owner too, so the next account to open the app doesn't
        // reopen this one's bucket before its own id is known.
        defaults.removeObject(forKey: Self.lastOwnerKey)
        let key = Self.key(for: nil)
        total = defaults.integer(forKey: Self.totalKey(key))
        ledger = Self.loadLedger(from: defaults, key: Self.ledgerKey(key))
        lastAward = nil
        pendingLevelUp = nil
    }

    // MARK: - Storage

    /// The last account to sign in on this device — see `init`.
    private static let lastOwnerKey = "xp.lastOwner"

    private static func key(for userId: Int?) -> String {
        userId.map { "xp.user.\($0)" } ?? "xp.signedOut"
    }

    private static func totalKey(_ base: String) -> String { "\(base).total" }
    private static func ledgerKey(_ base: String) -> String { "\(base).ledger" }

    private static func loadLedger(from defaults: UserDefaults, key: String) -> Set<String> {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return decoded
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Matches `StreakStore`'s day key, so the streak and its XP agree on where
    /// a day ends.
    private static func dayKey(for date: Date) -> String { dayFormatter.string(from: date) }

    private func persist() {
        let base = Self.key(for: userId)
        defaults.set(total, forKey: Self.totalKey(base))
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: Self.ledgerKey(base))
    }
}

extension XPStore {
    /// In-memory store for previews, so previews never touch real defaults.
    static func preview(total: Int = 0) -> XPStore {
        let store = XPStore(
            defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        )
        store.total = total
        return store
    }
}
