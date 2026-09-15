import Foundation

@MainActor
@Observable
final class StreakStore {
    private(set) var activeDays: Set<String>
    private let defaults: UserDefaults
    private var userId: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let owner = defaults.object(forKey: Self.lastOwnerKey) as? Int
        self.userId = owner
        self.activeDays = Self.load(from: defaults, key: Self.key(for: owner))
    }

    func recordActivity(on date: Date = Date()) {
        let key = Self.dayKey(for: date)
        guard !activeDays.contains(key) else { return }
        activeDays.insert(key)
        persist()
    }

    var didPracticeToday: Bool { activeDays.contains(Self.dayKey(for: Date())) }

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

    var weekProgress: [Bool] {
        weekDays.map { activeDays.contains(Self.dayKey(for: $0)) }
    }

    var todayIndexInWeek: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return weekDays.firstIndex { calendar.isDate($0, inSameDayAs: today) } ?? 0
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: today) else { return [today] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func adopt(userId: Int) {
        guard self.userId != userId else { return }
        self.userId = userId
        defaults.set(userId, forKey: Self.lastOwnerKey)
        activeDays = Self.load(from: defaults, key: Self.key(for: userId))
    }

    func clear() {
        userId = nil
        defaults.removeObject(forKey: Self.lastOwnerKey)
        activeDays = Self.load(from: defaults, key: Self.key(for: nil))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
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
