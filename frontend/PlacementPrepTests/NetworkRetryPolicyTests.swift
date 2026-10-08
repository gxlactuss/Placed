import Foundation
import Testing
@testable import PlacementPrep

@Suite("Network retry policy")
struct NetworkRetryPolicyTests {

    private func delay(
        attempt: Int = 1,
        method: String = "GET",
        status: Int? = nil,
        urlError: URLError.Code? = nil,
        retryAfter: TimeInterval? = nil,
        jitter: Double = 0
    ) -> TimeInterval? {
        NetworkManager.retryDelay(
            forAttempt: attempt,
            method: method,
            statusCode: status,
            urlErrorCode: urlError,
            retryAfter: retryAfter,
            jitter: jitter
        )
    }

    // MARK: Backoff schedule

    @Test func backoffIsHalfSecondThenOneAndAHalf() {
        #expect(delay(attempt: 1, urlError: .timedOut) == 0.5)
        #expect(delay(attempt: 2, urlError: .timedOut) == 1.5)
    }

    @Test func givesUpAfterTwoRetries() {
        #expect(delay(attempt: 3, urlError: .timedOut) == nil)
        #expect(delay(attempt: 3, status: 503) == nil)
        #expect(delay(attempt: 0, urlError: .timedOut) == nil)
    }

    @Test func jitterIsClampedToTwentyPercent() throws {
        let high = try #require(delay(attempt: 1, urlError: .timedOut, jitter: 0.9))
        let low = try #require(delay(attempt: 2, urlError: .timedOut, jitter: -0.9))
        #expect(abs(high - 0.6) < 1e-9)
        #expect(abs(low - 1.2) < 1e-9)
    }

    @Test func defaultRandomJitterStaysInRange() throws {
        for _ in 0..<200 {
            let first = try #require(NetworkManager.retryDelay(
                forAttempt: 1, method: "GET", statusCode: nil,
                urlErrorCode: .networkConnectionLost, retryAfter: nil
            ))
            let second = try #require(NetworkManager.retryDelay(
                forAttempt: 2, method: "GET", statusCode: 504,
                urlErrorCode: nil, retryAfter: nil
            ))
            #expect((0.4...0.6).contains(first))
            #expect((1.2...1.8).contains(second))
        }
    }

    // MARK: Method

    @Test(arguments: ["POST", "PUT", "PATCH", "DELETE"])
    func nonGetMethodsAreNeverRetried(method: String) {
        #expect(delay(method: method, urlError: .timedOut) == nil)
        #expect(delay(method: method, status: 503) == nil)
    }

    @Test func methodMatchIsCaseInsensitive() {
        #expect(delay(method: "get", status: 502) == 0.5)
    }

    // MARK: Transport errors

    @Test(arguments: [
        URLError.Code.timedOut, .networkConnectionLost, .notConnectedToInternet,
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
    ])
    func retryableURLErrors(code: URLError.Code) {
        #expect(delay(urlError: code) == 0.5)
    }

    @Test(arguments: [
        URLError.Code.cancelled, .badURL, .badServerResponse,
        .secureConnectionFailed, .userAuthenticationRequired, .unknown,
    ])
    func nonRetryableURLErrors(code: URLError.Code) {
        #expect(delay(urlError: code) == nil)
    }

    // MARK: HTTP status

    @Test(arguments: [502, 503, 504])
    func retryableStatusCodes(status: Int) {
        #expect(delay(status: status) == 0.5)
    }

    @Test(arguments: [400, 401, 403, 404, 409, 422, 429, 500, 501, 505])
    func nonRetryableStatusCodes(status: Int) {
        #expect(delay(status: status) == nil)
    }

    @Test func noFailureInfoMeansNoRetry() {
        #expect(delay() == nil)
    }

    // MARK: Retry-After

    @Test func shortRetryAfterIsHonouredWithoutJitter() {
        #expect(delay(status: 503, retryAfter: 3, jitter: 0.2) == 3)
        #expect(delay(status: 503, retryAfter: 5) == 5)
        #expect(delay(status: 503, retryAfter: 0) == 0)
    }

    @Test func longRetryAfterFallsBackToBackoff() {
        #expect(delay(status: 503, retryAfter: 30) == 0.5)
        #expect(delay(attempt: 2, status: 503, retryAfter: 5.1) == 1.5)
    }

    @Test func retryAfterDoesNotMakeNonRetryableStatusRetryable() {
        #expect(delay(status: 429, retryAfter: 1) == nil)
        #expect(delay(method: "POST", status: 503, retryAfter: 1) == nil)
    }

    @Test func parseRetryAfterSeconds() {
        #expect(NetworkManager.parseRetryAfter("3") == 3)
        #expect(NetworkManager.parseRetryAfter(" 2 ") == 2)
        #expect(NetworkManager.parseRetryAfter("-1") == nil)
        #expect(NetworkManager.parseRetryAfter("soon") == nil)
        #expect(NetworkManager.parseRetryAfter("") == nil)
        #expect(NetworkManager.parseRetryAfter(nil) == nil)
    }

    @Test func parseRetryAfterHTTPDate() {
        let now = ISO8601DateFormatter().date(from: "2015-10-21T07:28:00Z")!
        #expect(NetworkManager.parseRetryAfter("Wed, 21 Oct 2015 07:28:04 GMT", now: now) == 4)
        #expect(NetworkManager.parseRetryAfter("Wed, 21 Oct 2015 07:27:00 GMT", now: now) == 0)
    }
}
