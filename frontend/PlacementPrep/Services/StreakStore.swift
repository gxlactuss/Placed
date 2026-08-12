import Foundation

/// The daily practice streak — how many days in a row the student has done
/// *something* real in the app.
///
/// "Something real" is deliberately broad: finishing a quiz, ticking a DSA
/// problem solved, or completing a mock interview all count the same. The streak
/// rewards showing up, so gating it on one activity would punish a day spent
/// entirely on LeetCode. Every call site funnels through `recordActivity()`.
///
/// Storage is a set of day keys (`yyyy-MM-dd`, local time) rather than a
/// `(current, best, lastDate)` triple: with the raw days kept, both the current
/// and the best streak — and the week strip on Home — are derived, so a clock
/// change or a missed write can't leave a counter permanently wrong.
///
/// **Scoped per account, device-local.** Like `SavedQuestionsStore` there is no
/// server table behind this yet, so each user gets their own defaults bucket
/// (one account's streak must not become another's). Trade-off: the streak does
/// not follow the account to a second device.
@MainActor
@Observable
final class StreakStore {

    /// Day keys on which the student practised, e.g. "2026-08-12".
    private(set) var activeDays: Set<String>
    private let defaults: UserDefaults
    /// Whose streak is loaded. `nil` before sign-in — activity then lands in its
    /// own bucket rather than leaking into the next account.
    private var userId: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Reopen the last signed-in user's bucket: on an offline relaunch the
        // tabs appear before `/me` resolves, and a day practised in that window
        // must not be recorded against a bucket the account never sees.
        let owner = defaults.object(forKey: Self.lastOwnerKey) as? Int
        self.userId = owner
        self.activeDays = Self.load(from: defaults, key: Self.key(for: owner))
    }

    // MARK: - Recording

    /// Marks `date`'s day as practised. Idempotent, so the twenty callers on a
    /// busy day cost one write between them.
    func recordActivity(on date: Date = Date()) {
        let key = Self.dayKey(for: date)
        guard !activeDays.contains(key) else { return }
        activeDays.insert(key)
        persist()
    }

    // MARK: - Derived state

    var didPracticeToday: Bool { activeDays.contains(Self.dayKey(for: Date())) }

    /// Consecutive practised days ending today.
    ///
    /// A streak stays alive all through the day after the last one: if today is
    /// still untouched we count back from yesterday, so the number on Home is
    /// "your streak" rather than "your streak, already broken at 00:01".
    var currentStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var cursor: Date
        if activeDays.contains(Self.dayKey(for: today)) {
            cursor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  activeDays.contains(Self.dayKey(for: yesterday)) {
            cursor = yesterday
        } else {
            return 0
        }

        var count = 0
        while activeDays.contains(Self.dayKey(for: cursor)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// The longest run ever recorded — never less than the current one.
    var bestStreak: Int {
        let calendar = Calendar.current
        let days = activeDays.compactMap(Self.date(fromDayKey:)).sorted()
        guard !days.isEmpty else { return 0 }

        var best = 1
        var run = 1
        for (previous, day) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            run = gap == 1 ? run + 1 : 1
            best = max(best, run)
        }
        return best
    }

    /// The current calendar week, one flag per day from the locale's first
    /// weekday — what the dot strip on Home draws.
    var weekProgress: [Bool] {
        weekDays.map { activeDays.contains(Self.dayKey(for: $0)) }
    }

    /// Where today sits in `weekProgress`, so the strip can ring it.
    var todayIndexInWeek: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return weekDays.firstIndex { calendar.isDate($0, inSameDayAs: today) } ?? 0
    }

    /// The seven days of the week containing today, in display order.
    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // `weekday` is 1-based from Sunday; shift it so the locale's first
        // weekday lands at offset 0.
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: today) else { return [today] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: - Account scoping

    /// Loads `userId`'s streak. Called wherever the other stores sync; like
    /// `SavedQuestionsStore.adopt` there is no server side to reconcile, so
    /// switching accounts just swaps which bucket is in memory.
    func adopt(userId: Int) {
        guard self.userId != userId else { return }
        self.userId = userId
        defaults.set(userId, forKey: Self.lastOwnerKey)
        activeDays = Self.load(from: defaults, key: Self.key(for: userId))
    }

    /// Drops the signed-in user's days from memory on sign-out. Their bucket is
    /// left on disk so signing back in restores the streak — so this must not
    /// `persist()`, which would write the empty set over it.
    func clear() {
        userId = nil
        defaults.removeObject(forKey: Self.lastOwnerKey)
        activeDays = Self.load(from: defaults, key: Self.key(for: nil))
    }

    // MARK: - Storage

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Fixed locale/calendar: the key is storage, not something a user reads,
        // so it must not change shape with the device's region.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func date(fromDayKey key: String) -> Date? {
        dayFormatter.date(from: key)
    }

    /// The last account to sign in on this device — see `init`.
    private static let lastOwnerKey = "practiceStreak.lastOwner"

    private static func key(for userId: Int?) -> String {
        userId.map { "practiceStreakDays.user.\($0)" } ?? "practiceStreakDays.signedOut"
    }

    private static func load(from defaults: UserDefaults, key: String) -> Set<String> {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(activeDays) else { return }
        defaults.set(data, forKey: Self.key(for: userId))
    }
}

extension StreakStore {
    /// In-memory store for previews, so previews never touch real defaults.
    /// `daysBack` seeds a run ending today, e.g. `preview(daysBack: 3)`.
    static func preview(daysBack: Int = 0) -> StreakStore {
        let store = StreakStore(
            defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        )
        let calendar = Calendar.current
        for offset in 0..<max(0, daysBack) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: Date()) {
                store.recordActivity(on: day)
            }
        }
        return store
    }
}
