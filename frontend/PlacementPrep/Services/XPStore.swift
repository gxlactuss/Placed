import Foundation

@MainActor
@Observable
final class XPStore {

    private(set) var total: Int
    private(set) var ledger: Set<String>
    private(set) var lastAward: XPAward?
    var pendingLevelUp: XPLevel?

    private let defaults: UserDefaults
    private var userId: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let owner = defaults.object(forKey: Self.lastOwnerKey) as? Int
        let key = Self.key(for: owner)
        self.userId = owner
        self.total = defaults.integer(forKey: Self.totalKey(key))
        self.ledger = Self.loadLedger(from: defaults, key: Self.ledgerKey(key))
    }

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

    @discardableResult
    func awardStreakDay(on date: Date = Date()) -> Int {
        award(.streakDay(Self.dayKey(for: date)))
    }

    func hasAwarded(_ award: XPAward) -> Bool { ledger.contains(award.ledgerKey) }

    var level: XPLevel { XPLevel.level(for: total) }

    var nextLevel: XPLevel? { level.next }

    var xpIntoLevel: Int { total - level.minimumXP }

    var xpForLevel: Int? {
        guard let next = nextLevel else { return nil }
        return next.minimumXP - level.minimumXP
    }

    var xpToNextLevel: Int? {
        guard let next = nextLevel else { return nil }
        return max(0, next.minimumXP - total)
    }

    var progressInLevel: Double {
        guard let span = xpForLevel, span > 0 else { return 1 }
        return min(1, Double(xpIntoLevel) / Double(span))
    }

    var unlockedLevels: [XPLevel] { XPLevel.allCases.filter { total >= $0.minimumXP } }

    func isUnlocked(_ level: XPLevel) -> Bool { total >= level.minimumXP }

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

    func clear() {
        userId = nil
        defaults.removeObject(forKey: Self.lastOwnerKey)
        let key = Self.key(for: nil)
        total = defaults.integer(forKey: Self.totalKey(key))
        ledger = Self.loadLedger(from: defaults, key: Self.ledgerKey(key))
        lastAward = nil
        pendingLevelUp = nil
    }

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

    private static func dayKey(for date: Date) -> String { dayFormatter.string(from: date) }

    private func persist() {
        let base = Self.key(for: userId)
        defaults.set(total, forKey: Self.totalKey(base))
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: Self.ledgerKey(base))
    }
}

extension XPStore {
    static func preview(total: Int = 0) -> XPStore {
        let store = XPStore(
            defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        )
        store.total = total
        return store
    }
}
