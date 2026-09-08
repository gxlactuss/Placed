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

/// Thin async/await wrapper around URLSession for talking to the FastAPI backend.
final class NetworkManager {
    static let shared = NetworkManager()

    /// Where the backend lives. Resolved once at init, in priority order:
    ///
    ///   1. the `PPBackendURL` user default, if it parses
    ///   2. `compiledBackendURL` below
    ///
    /// The override exists because the Mac build is handed around as a `.dmg`
    /// (see DISTRIBUTE-MAC.md), and a `.dmg` that hardcodes its backend can only
    /// ever be repointed by someone with Xcode. One default write repoints it:
    ///
    ///     defaults write ~/Library/Preferences/com.placementprep.app \
    ///       PPBackendURL "http://192.168.1.5:8000"
    ///
    /// Write the **path**, not the bundle id. `defaults write com.placementprep.app`
    /// looks equivalent and isn't: if a sandboxed build of the same bundle id has
    /// ever run on that Mac, macOS silently redirects the write into
    /// `~/Library/Containers/.../Preferences/`, and the unsigned `.dmg` build —
    /// which carries no entitlements and so is *not* sandboxed — keeps reading
    /// the plain path and never sees it. That is not hypothetical; it is what
    /// happened the first time this was tested on a machine that had also run
    /// the Debug build. The path form is unambiguous on both.
    ///
    /// On iOS the key simply goes unset and the compiled default wins.
    private let baseURL: URL

    /// There is deliberately no hosted backend to point Release at: this ships to
    /// a couple of developers who each run the API themselves. If one ever gets
    /// deployed, this is the line to change — and `DISTRIBUTE-MAC.md`'s checklist
    /// is the reminder to change it before cutting a build.
    private static let compiledBackendURL = URL(string: "http://localhost:8000")!

    /// Rejects a malformed override rather than trapping on it: a typo in a
    /// `defaults write` should fall back to the compiled default, not refuse to
    /// launch the app.
    static func resolveBaseURL(
        defaults: UserDefaults = .standard,
        fallback: URL = NetworkManager.compiledBackendURL
    ) -> URL {
        guard let raw = defaults.string(forKey: "PPBackendURL")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme == "http" || url.scheme == "https",
              url.host != nil
        else { return fallback }
        return url
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Injected so ViewModels can attach the bearer token without NetworkManager
    /// owning auth state itself.
    var authTokenProvider: (() -> String?)?

    /// Fired when an *authenticated* request comes back 401 — i.e. the stored
    /// session has lapsed. The auth layer uses this to drop back to login.
    var onUnauthorized: (() -> Void)?

    private init(session: URLSession? = nil) {
        self.baseURL = Self.resolveBaseURL()

        // A bounded timeout so an unreachable backend fails fast instead of
        // hanging the launch splash (which waits on `/api/auth/me`).
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }

        let decoder = JSONDecoder()
        // The backend emits two flavours of timestamp: timezone-aware ISO8601
        // for freshly generated values, and *naive* strings with microseconds
        // (e.g. "2026-07-24T12:45:15.865875") for datetimes round-tripped through
        // SQLite. The stock `.iso8601` strategy rejects both fractional seconds
        // and a missing timezone, so we parse leniently across the known shapes.
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

    /// The backend URL that starts a social sign-in flow for `provider`.
    func oauthLoginURL(provider: String) -> URL {
        URL(string: "/api/auth/oauth/\(provider)/login", relativeTo: baseURL)!.absoluteURL
    }

    /// Performs a request and decodes the JSON response body.
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

    /// Performs a request and ignores the response body — for endpoints that
    /// return 204 No Content (e.g. marking a problem solved).
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

    /// Uploads a file as `multipart/form-data` and decodes the JSON response —
    /// used for the spoken-answer recording, which can't go through the JSON
    /// body path.
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

    /// Sends a prepared request and maps the status code — shared by the JSON
    /// and multipart paths so 401 handling can't drift between them.
    private func perform(_ urlRequest: URLRequest, requiresAuth: Bool) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw NetworkError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.server(statusCode: -1, message: "No HTTP response")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return data
        case 401:
            // Only a lapsed *session* should bounce to login — a 401 on an
            // unauthenticated call (e.g. wrong password on login) is not that.
            if requiresAuth { onUnauthorized?() }
            throw NetworkError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.server(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

/// Tolerant parser for the timestamp shapes the backend can produce.
/// Tries, in order: ISO8601 with timezone (± fractional seconds), then
/// timezone-naive strings (assumed UTC, ± fractional seconds).
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

/// Type-erasing wrapper so `request` can accept any Encodable body.
private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self.encodeClosure = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
