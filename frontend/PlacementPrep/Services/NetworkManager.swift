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

    private static let compiledBackendURL = URL(string: "http://localhost:8000")!

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
            if requiresAuth { onUnauthorized?() }
            throw NetworkError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.server(statusCode: httpResponse.statusCode, message: message)
        }
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
