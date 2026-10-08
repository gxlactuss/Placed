import Foundation
import Testing
@testable import PlacementPrep

@Suite("LenientDate")
struct LenientDateTests {

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    @Test func isoWithoutFraction() throws {
        let date = try #require(LenientDate.parse("2024-05-01T12:34:56Z"))
        #expect(date == utc(2024, 5, 1, 12, 34, 56))
    }

    @Test func isoWithFraction() throws {
        let date = try #require(LenientDate.parse("2024-05-01T12:34:56.789Z"))
        #expect(abs(date.timeIntervalSince(utc(2024, 5, 1, 12, 34, 56)) - 0.789) < 0.001)
    }

    @Test func isoWithOffset() throws {
        let date = try #require(LenientDate.parse("2024-05-01T12:34:56+05:30"))
        #expect(date == utc(2024, 5, 1, 7, 4, 56))
        let fractional = try #require(LenientDate.parse("2024-05-01T12:34:56.500000+00:00"))
        #expect(abs(fractional.timeIntervalSince(utc(2024, 5, 1, 12, 34, 56)) - 0.5) < 0.001)
    }

    @Test func naiveTimestampIsUTC() throws {
        let date = try #require(LenientDate.parse("2024-05-01T12:34:56"))
        #expect(date == utc(2024, 5, 1, 12, 34, 56))
    }

    @Test func naiveTimestampWithMicroseconds() throws {
        let date = try #require(LenientDate.parse("2024-05-01T12:34:56.123456"))
        #expect(abs(date.timeIntervalSince(utc(2024, 5, 1, 12, 34, 56)) - 0.123456) < 0.001)
    }

    @Test(arguments: [
        "",
        "not a date",
        "12/05/2024",
        "2024-13-45T99:99:99",
        "2024-05-01T12:34",
        "1714566896",
    ])
    func invalidStringsReturnNil(raw: String) {
        #expect(LenientDate.parse(raw) == nil)
    }
}

@Suite("NetworkManager.resolveBaseURL")
struct ResolveBaseURLTests {

    private let fallback = URL(string: "https://fallback.example")!

    /// Runs `body` against a throwaway defaults suite so nothing leaks into the app's defaults.
    private func withDefaults(_ value: String?, _ body: (UserDefaults) -> Void) {
        let name = "PlacementPrepTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        if let value { defaults.set(value, forKey: "PPBackendURL") }
        body(defaults)
    }

    @Test func missingValueFallsBack() {
        withDefaults(nil) { defaults in
            #expect(NetworkManager.resolveBaseURL(defaults: defaults, fallback: fallback) == fallback)
        }
    }

    #if DEBUG
    /// Tests run the Debug config, whose Info.plist PPBackendURL is localhost.
    @Test func debugBuildDefaultsToLocalhost() {
        withDefaults(nil) { defaults in
            #expect(NetworkManager.resolveBaseURL(defaults: defaults).absoluteString == "http://localhost:8000")
        }
    }

    @Test func debugBuildHonorsLoopbackOverride() {
        withDefaults("http://127.0.0.1:9000") { defaults in
            let url = NetworkManager.resolveBaseURL(defaults: defaults, fallback: fallback)
            #expect(url.absoluteString == "http://127.0.0.1:9000")
        }
    }
    #endif

    @Test(arguments: [
        "",
        "   \n",
        "ftp://example.com",
        "file:///etc/hosts",
        "javascript:alert(1)",
        "localhost:8000",
        "example.com",
        "https://",
        "not a url",
    ])
    func badValuesFallBack(raw: String) {
        withDefaults(raw) { defaults in
            #expect(NetworkManager.resolveBaseURL(defaults: defaults, fallback: fallback) == fallback)
        }
    }

    @Test(arguments: [
        ("https://placementprep-api.fly.dev", "https://placementprep-api.fly.dev"),
        ("  https://api.example.com\n", "https://api.example.com"),
        ("http://192.168.1.10:8000", "http://192.168.1.10:8000"),
    ])
    func validValuesAreUsed(raw: String, expected: String) {
        withDefaults(raw) { defaults in
            let url = NetworkManager.resolveBaseURL(defaults: defaults, fallback: fallback)
            #expect(url.absoluteString == expected)
        }
    }

    @Test func nonStringValueFallsBack() {
        let name = "PlacementPrepTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["https://example.com"], forKey: "PPBackendURL")
        #expect(NetworkManager.resolveBaseURL(defaults: defaults, fallback: fallback) == fallback)
    }
}

@Suite("NetworkError.userMessage")
struct NetworkErrorMessageTests {

    @Test func serverDetailBodyIsUnwrapped() {
        let error = NetworkError.server(statusCode: 400, message: #"{"detail": "x"}"#)
        #expect(NetworkError.userMessage(for: error) == "x")
    }

    @Test func serverDetailWithExtraFields() {
        let error = NetworkError.server(statusCode: 409, message: #"{"detail":"Email already registered","code":1}"#)
        #expect(NetworkError.userMessage(for: error) == "Email already registered")
    }

    @Test func unauthorizedHasFriendlyMessage() {
        #expect(NetworkError.userMessage(for: NetworkError.unauthorized)
            == "Your session expired. Log in again to continue.")
    }

    @Test func nonJSONServerBodyFallsBackToDescription() {
        let error = NetworkError.server(statusCode: 500, message: "Internal Server Error")
        let message = NetworkError.userMessage(for: error)
        #expect(message == error.localizedDescription)
        #expect(message.contains("500"))
    }

    @Test func decodingError() {
        struct Dummy: Error {}
        let error = NetworkError.decoding(Dummy())
        #expect(NetworkError.userMessage(for: error) == "Failed to parse server response.")
    }

    @Test func transportErrorUsesUnderlyingDescription() {
        let underlying = URLError(.notConnectedToInternet)
        let message = NetworkError.userMessage(for: NetworkError.transport(underlying))
        #expect(message == underlying.localizedDescription)
    }

    @Test func invalidURL() {
        #expect(NetworkError.userMessage(for: NetworkError.invalidURL) == "Invalid URL.")
    }

    @Test func foreignErrorUsesLocalizedDescription() {
        struct Custom: LocalizedError { var errorDescription: String? { "Custom failure" } }
        #expect(NetworkError.userMessage(for: Custom()) == "Custom failure")
    }
}
