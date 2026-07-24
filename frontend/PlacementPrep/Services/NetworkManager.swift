import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
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

    /// Debug builds talk to a local backend; Release builds talk to the deployed
    /// Fly.io app. Keep the Release host in sync with `fly.toml`'s `app` name
    /// (Fly serves it at `https://<app>.fly.dev`).
    #if DEBUG
    private let baseURL = URL(string: "http://localhost:8000")!
    #else
    private let baseURL = URL(string: "https://placementprep-api.fly.dev")!
    #endif

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Injected so ViewModels can attach the bearer token without NetworkManager
    /// owning auth state itself.
    var authTokenProvider: (() -> String?)?

    private init(session: URLSession = .shared) {
        self.session = session

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

    func request<Response: Decodable>(
        path: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> Response {
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
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw NetworkError.decoding(error)
            }
        case 401:
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
