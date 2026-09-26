import CryptoKit
import Foundation

@MainActor
@Observable
final class ResumeReviewStore {

    private(set) var reviews: [SavedResumeReview] = []

    private let defaults: UserDefaults
    private var userId: Int?
    private static let limit = 10

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var latest: SavedResumeReview? { reviews.first }

    func adopt(userId: Int) {
        guard self.userId != userId else { return }
        self.userId = userId
        reviews = load(for: userId)
    }

    func clear() {
        userId = nil
        reviews = []
    }

    func cached(hash: String) -> SavedResumeReview? {
        reviews.first { $0.textHash == hash }
    }

    func previousScore(before saved: SavedResumeReview) -> Int? {
        guard let index = reviews.firstIndex(where: { $0.id == saved.id }),
              reviews.indices.contains(index + 1) else { return nil }
        return reviews[index + 1].review.overall
    }

    func record(_ saved: SavedResumeReview) {
        reviews.removeAll { $0.textHash == saved.textHash }
        reviews.insert(saved, at: 0)
        reviews = Array(reviews.prefix(Self.limit))
        guard let userId, let data = try? JSONEncoder().encode(reviews) else { return }
        defaults.set(data, forKey: Self.key(for: userId))
    }

    static func hash(text: String, role: String) -> String {
        let digest = SHA256.hash(data: Data("\(role)\n\(text)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func load(for userId: Int) -> [SavedResumeReview] {
        guard let data = defaults.data(forKey: Self.key(for: userId)) else { return [] }
        return (try? JSONDecoder().decode([SavedResumeReview].self, from: data)) ?? []
    }

    private static func key(for userId: Int) -> String { "resumeReviews.user.\(userId)" }
}

extension ResumeReviewStore {
    static func preview(_ saved: [SavedResumeReview] = []) -> ResumeReviewStore {
        let store = ResumeReviewStore(
            defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        )
        store.adopt(userId: 1)
        saved.reversed().forEach(store.record)
        return store
    }
}
