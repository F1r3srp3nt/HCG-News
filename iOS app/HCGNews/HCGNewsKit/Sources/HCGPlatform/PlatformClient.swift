import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import NewsCore

/// Failures from the HCG platform, normalised for honest UI states.
public enum PlatformError: Error, Equatable, Sendable {
    case offline
    case timedOut
    case insecureConnection
    /// The access token was missing, expired or revoked (HTTP 401, or JWT errors).
    case unauthorized
    /// The server refused this operation for this account (HTTP 403, or row-level security).
    case forbidden(String?)
    case notFound
    /// Someone else changed the record since it was loaded.
    case conflict
    case rateLimited
    case unavailable
    /// The response didn't match the discovered contract.
    case contract(String)
    case server(status: Int, message: String?)
    case other(String)

    /// A sentence safe to show to the user.
    public var message: String {
        switch self {
        case .offline: "You're offline. Nothing was changed on the server."
        case .timedOut: "HCG didn't answer in time. Nothing was confirmed; try again."
        case .insecureConnection: "The secure connection to HCG failed, so nothing was sent."
        case .unauthorized: "Your HCG session has expired or was revoked. Sign in again."
        case .forbidden(let detail): "Your HCG News role doesn't allow this." + (detail.map { " (\($0))" } ?? "")
        case .notFound: "It no longer exists, or your account can't see it."
        case .conflict: "This was changed by someone else since you opened it."
        case .rateLimited: "Too many requests. Wait about a minute and try again."
        case .unavailable: "HCG is temporarily unavailable. Try again shortly."
        case .contract(let detail): "HCG answered in an unexpected way (\(detail))."
        case .server(let status, let message): "HCG returned an error (\(status))" + (message.map { ": \($0)" } ?? ".")
        case .other(let detail): detail
        }
    }
}

/// Low-level access to the shared HCG project (PostgREST, Auth, Storage) and the
/// HCG website's mobile routes. Every request carries the public client key; requests
/// on behalf of a person also carry their access token, and the server authorises them.
public struct PlatformClient: Sendable {
    public let configuration: HCGPlatformConfiguration
    let transport: HTTPTransport
    let userAgent: String

    public init(configuration: HCGPlatformConfiguration, transport: HTTPTransport, userAgent: String) {
        self.configuration = configuration
        self.transport = transport
        self.userAgent = userAgent
    }

    // MARK: Requests

    func restRequest(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil,
                     token: String?, prefer: String? = nil) throws -> URLRequest {
        var components = URLComponents(url: configuration.restURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.percentEncodedQueryItems = query.map(Self.encode) }
        guard let url = components?.url else { throw PlatformError.other("Couldn't build the request.") }
        var request = baseRequest(url, method: method, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        return request
    }

    func baseRequest(_ url: URL, method: String, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(configuration.publicClientKey, forHTTPHeaderField: "apikey")
        // Without a person's token, PostgREST/Storage run as the anonymous role.
        request.setValue("Bearer \(token ?? configuration.publicClientKey)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Percent-encodes a PostgREST query item. PostgREST operators (`eq.`, `or=(…)`) keep
    /// their punctuation; reserved URL characters in values are encoded.
    static func encode(_ item: URLQueryItem) -> URLQueryItem {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#")
        return URLQueryItem(name: item.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? item.name,
                            value: item.value?.addingPercentEncoding(withAllowedCharacters: allowed))
    }

    // MARK: Sending

    /// Sends a request and maps failures. 2xx responses return their body.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as TransportError {
            switch error {
            case .offline: throw PlatformError.offline
            case .timedOut: throw PlatformError.timedOut
            case .insecureConnection: throw PlatformError.insecureConnection
            case .invalidResponse: throw PlatformError.contract("not an HTTP response")
            case .other(let detail): throw PlatformError.other("Network error: \(detail)")
            }
        }
        if (200..<300).contains(response.statusCode) { return (data, response) }
        throw Self.error(status: response.statusCode, body: data)
    }

    static func error(status: Int, body: Data) -> PlatformError {
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let code = (object?["code"] as? String) ?? (object?["error_code"] as? String) ?? (object?["error"] as? String)
        let message = (object?["message"] as? String) ?? (object?["msg"] as? String)
            ?? (object?["error_description"] as? String)
        let lowered = (message ?? "").lowercased()
        // PostgREST reports an expired JWT as 401 PGRST301/PGRST303; RLS violations as 42501.
        if status == 401 || code == "PGRST301" || code == "PGRST303" || lowered.contains("jwt expired") {
            return .unauthorized
        }
        if status == 403 || code == "42501" || lowered.contains("row-level security") {
            return .forbidden(message.map(Self.safeDetail))
        }
        switch status {
        case 404, 406: return .notFound
        case 409: return .conflict
        case 410: return .notFound
        case 429: return .rateLimited
        case 502, 503, 504: return .unavailable
        default: return .server(status: status, message: message.map(Self.safeDetail))
        }
    }

    /// Server messages are shown to staff; keep them short.
    static func safeDetail(_ text: String) -> String {
        String(text.prefix(200))
    }

    // MARK: JSON helpers

    func json(_ request: URLRequest) async throws -> Any {
        let (data, _) = try await send(request)
        if data.isEmpty { return NSNull() }
        do { return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw PlatformError.contract("invalid JSON") }
    }

    func rows(_ request: URLRequest) async throws -> [[String: Any]] {
        guard let rows = try await json(request) as? [[String: Any]] else { throw PlatformError.contract("expected a list") }
        return rows
    }

    static func body(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object.mapValues { $0 is NSNull ? NSNull() : $0 }, options: [.sortedKeys])
    }
}

/// Typed reading of PostgREST JSON rows.
struct Row {
    let raw: [String: Any]
    init(_ raw: [String: Any]) { self.raw = raw }

    func string(_ key: String) -> String? {
        if let s = raw[key] as? String { return s }
        if let n = raw[key] as? NSNumber, !(raw[key] is Bool) { return n.stringValue }
        return nil
    }
    func nonEmpty(_ key: String) -> String? {
        guard let s = string(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
    func bool(_ key: String) -> Bool { (raw[key] as? Bool) ?? false }
    func int(_ key: String) -> Int? { (raw[key] as? NSNumber)?.intValue ?? string(key).flatMap { Int($0) } }
    func date(_ key: String) -> Date? { string(key).flatMap(HCGJSON.parseDate) }
    func url(_ key: String) -> URL? { nonEmpty(key).flatMap { URL(string: $0) } }
    func strings(_ key: String) -> [String] { (raw[key] as? [Any])?.compactMap { $0 as? String } ?? [] }
    /// An embedded single relation (PostgREST returns an object, or null).
    func embedded(_ key: String) -> Row? {
        if let object = raw[key] as? [String: Any] { return Row(object) }
        if let list = raw[key] as? [[String: Any]], let first = list.first { return Row(first) }
        return nil
    }
}
