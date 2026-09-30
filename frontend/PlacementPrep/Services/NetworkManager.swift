import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case server(statusCode: Int, message: String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .unauthorized: return "Session expired. Please log in again."
        case .server(let code, let message): return "Server error (\(code)): \(message)"
        case .decoding: return "Failed to parse server response."
        case .transport(let error): return error.localizedDescription
        }
    }
}

extension NetworkError {
    static func userMessage(for error: Error) -> String {
        if case let NetworkError.server(_, body) = error,
           let data = body.data(using: .utf8),
           let detail = try? JSONDecoder().decode(ServerDetail.self, from: data) {
            return detail.detail
        }
        if case NetworkError.unauthorized = error {
            return "Your session expired. Log in again to continue."
        }
        return error.localizedDescription
    }

    private struct ServerDetail: Decodable { let detail: String }
}

final class NetworkManager {
    static let shared = NetworkManager()

    private let baseURL: URL

    /// Backend URL baked in at build time: `PPBackendURL` in Info.plist, which is set from the
    /// `PP_BACKEND_URL` build setting (localhost for Debug, the Fly deployment for Release).
    private static let compiledBackendURL: URL =
        validatedBackendURL(Bundle.main.object(forInfoDictionaryKey: "PPBackendURL") as? String)
        ?? URL(string: "http://localhost:8000")!

    /// Accepts only absolute http(s) URLs with a host; anything else returns nil.
    private static func validatedBackendURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme == "http" || url.scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }

    private static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    /// The `PPBackendURL` user default overrides the compiled URL. Release builds ignore a
    /// loopback override so a stale developer setting can't point a shipped app at localhost.
    static func resolveBaseURL(
        defaults: UserDefaults = .standard,
        fallback: URL = NetworkManager.compiledBackendURL
    ) -> URL {
        guard let url = validatedBackendURL(defaults.string(forKey: "PPBackendURL")) else {
            return fallback
        }
        #if !DEBUG
        if isLoopback(url) { return fallback }
        #endif
        return url
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    var authTokenProvider: (() -> String?)?

    var onUnauthorized: (() -> Void)?

    private init(session: URLSession? = nil) {
        self.baseURL = Self.resolveBaseURL()

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = LenientDate.parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unrecognized date format: \(raw)"
                )
            }
            return date
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func oauthLoginURL(provider: String) -> URL {
        URL(string: "/api/auth/oauth/\(provider)/login", relativeTo: baseURL)!.absoluteURL
    }

    func request<Response: Decodable>(
        path: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> Response {
        let data = try await rawRequest(path: path, method: method, body: body, requiresAuth: requiresAuth)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }

    func send(
        path: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws {
        _ = try await rawRequest(path: path, method: method, body: body, requiresAuth: requiresAuth)
    }

    private func rawRequest(
        path: String,
        method: HTTPMethod,
        body: Encodable?,
        requiresAuth: Bool
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw NetworkError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth, let token = authTokenProvider?() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            urlRequest.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return try await perform(urlRequest, requiresAuth: requiresAuth)
    }

    func upload<Response: Decodable>(
        path: String,
        fileURL: URL,
        fieldName: String,
        mimeType: String,
        requiresAuth: Bool = true
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw NetworkError.invalidURL
        }

        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw NetworkError.transport(error)
        }

        let boundary = "PPBoundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = HTTPMethod.post.rawValue
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if requiresAuth, let token = authTokenProvider?() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = body

        let data = try await perform(urlRequest, requiresAuth: requiresAuth)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }

    /// Sends `urlRequest`, retrying transient failures of idempotent GETs according to
    /// `retryDelay(forAttempt:method:statusCode:urlErrorCode:retryAfter:jitter:)`.
    /// Non-GET requests (including `upload`) are always sent exactly once.
    private func perform(_ urlRequest: URLRequest, requiresAuth: Bool) async throws -> Data {
        let method = urlRequest.httpMethod ?? HTTPMethod.get.rawValue
        var attempt = 1

        while true {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch {
                if !(error is CancellationError), !Task.isCancelled,
                   let delay = Self.retryDelay(
                       forAttempt: attempt,
                       method: method,
                       statusCode: nil,
                       urlErrorCode: (error as? URLError)?.code,
                       retryAfter: nil
                   ),
                   await Self.sleepBeforeRetry(delay) {
                    attempt += 1
                    continue
                }
                throw NetworkError.transport(error)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.server(statusCode: -1, message: "No HTTP response")
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return data
            case 401:
                // Never retried, so this fires at most once per request.
                if requiresAuth { onUnauthorized?() }
                throw NetworkError.unauthorized
            default:
                if !Task.isCancelled,
                   let delay = Self.retryDelay(
                       forAttempt: attempt,
                       method: method,
                       statusCode: httpResponse.statusCode,
                       urlErrorCode: nil,
                       retryAfter: Self.parseRetryAfter(httpResponse.value(forHTTPHeaderField: "Retry-After"))
                   ),
                   await Self.sleepBeforeRetry(delay) {
                    attempt += 1
                    continue
                }
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw NetworkError.server(statusCode: httpResponse.statusCode, message: message)
            }
        }
    }

    // MARK: - Retry policy

    /// Retries allowed after the first attempt (so at most 3 requests in total).
    static let maxRetries = 2
    /// Base delay before retry N (index 0 = first retry), before jitter.
    static let retryBackoff: [TimeInterval] = [0.5, 1.5]
    /// Jitter applied to the backoff, as a fraction of it.
    static let retryJitter: Double = 0.2
    /// A server-provided Retry-After is honoured only up to this many seconds.
    static let maxHonouredRetryAfter: TimeInterval = 5

    static let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .notConnectedToInternet,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
    ]

    static let retryableStatusCodes: Set<Int> = [502, 503, 504]

    /// Pure retry decision; returns the delay before the next attempt, or nil to give up.
    ///
    /// - Parameters:
    ///   - attempt: 1-based number of the attempt that just failed.
    ///   - method: HTTP method; only GET is ever retried.
    ///   - statusCode: HTTP status of the failed attempt, if a response arrived.
    ///   - urlErrorCode: URLError code of the failed attempt, if it failed at transport level.
    ///   - retryAfter: Parsed Retry-After seconds from the response, if any.
    ///   - jitter: Fraction applied to the backoff, clamped to ±`retryJitter`. Random by default.
    static func retryDelay(
        forAttempt attempt: Int,
        method: String,
        statusCode: Int?,
        urlErrorCode: URLError.Code?,
        retryAfter: TimeInterval?,
        jitter: Double = Double.random(in: -NetworkManager.retryJitter...NetworkManager.retryJitter)
    ) -> TimeInterval? {
        guard method.uppercased() == HTTPMethod.get.rawValue else { return nil }
        guard attempt >= 1, attempt <= maxRetries, attempt <= retryBackoff.count else { return nil }

        if let urlErrorCode {
            // Covers .cancelled and every other code not explicitly listed.
            guard retryableURLErrorCodes.contains(urlErrorCode) else { return nil }
        } else if let statusCode {
            // 4xx (including 429) and all other 5xx are never retried.
            guard retryableStatusCodes.contains(statusCode) else { return nil }
            if let retryAfter, retryAfter >= 0, retryAfter <= maxHonouredRetryAfter {
                return retryAfter
            }
        } else {
            return nil
        }

        let clampedJitter = min(max(jitter, -retryJitter), retryJitter)
        return retryBackoff[attempt - 1] * (1 + clampedJitter)
    }

    /// Parses a Retry-After header given either as delta-seconds or as an HTTP-date.
    static func parseRetryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw) {
            return seconds >= 0 ? seconds : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: raw) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    /// Sleeps for `delay`; returns false if the task was cancelled (so the caller stops retrying).
    private static func sleepBeforeRetry(_ delay: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
        } catch {
            return false
        }
        return !Task.isCancelled
    }
}

enum LenientDate {
    private static let iso8601: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [withFraction, plain]
    }()

    private static let naive: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"].map { format in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(identifier: "UTC")
            df.dateFormat = format
            return df
        }
    }()

    static func parse(_ string: String) -> Date? {
        for formatter in iso8601 {
            if let date = formatter.date(from: string) { return date }
        }
        for formatter in naive {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self.encodeClosure = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
