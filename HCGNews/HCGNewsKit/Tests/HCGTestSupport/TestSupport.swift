import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport

// TEST-ONLY SUPPORT. Every fixture here is fictional and exists only to exercise
// parsing and layout logic. None of it is HCG News reporting.

/// A scripted transport that records every request.
public final class FakeTransport: HTTPTransport, @unchecked Sendable {
    public typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private let lock = NSLock()
    private var handler: Handler
    private var recorded: [URLRequest] = []

    public init(_ handler: @escaping Handler = { _ in (500, Data()) }) {
        self.handler = handler
    }

    public func setHandler(_ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
    }

    public var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    private func record(_ request: URLRequest) -> Handler {
        lock.withLock {
            recorded.append(request)
            return handler
        }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let handler = record(request)
        let (status, data) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }
}

public enum JSONFixture {
    public static func data(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public static func iso(_ date: Date) -> String { HCGJSON.formatDate(date) }

    /// A fictional article summary dictionary in the PROPOSED wire format.
    public static func summary(id: String,
                               headline: String = "Test fixture headline",
                               publishedAt: Date = Date(timeIntervalSince1970: 1_790_000_000),
                               status: String? = "published",
                               access: String? = nil,
                               featured: Bool = false,
                               breaking: [String: Any]? = nil,
                               section: [String: Any]? = ["id": "s1", "slug": "test-section", "name": "Test Section"],
                               authors: [[String: Any]] = [],
                               extra: [String: Any] = [:]) -> [String: Any] {
        var object: [String: Any] = [
            "id": id,
            "slug": "test-\(id)",
            "canonicalUrl": "https://news.hakmicapitalgroup.com/articles/test-\(id)",
            "headline": headline,
            "standfirst": "Fictional standfirst used only in automated tests.",
            "editorialType": "news",
            "publishedAt": iso(publishedAt),
            "isFeatured": featured,
            "authors": authors,
        ]
        if let status { object["status"] = status }
        if let access { object["access"] = access }
        if let breaking { object["breaking"] = breaking }
        if let section { object["section"] = section }
        for (k, v) in extra { object[k] = v }
        return object
    }

    public static func meta(version: String = "1", search: Bool = false) -> [String: Any] {
        ["contractVersion": version, "capabilities": ["search": search]]
    }
}

/// Routes requests by the last path component(s) of the URL, relative to an API base.
public struct Router: Sendable {
    public let routes: [String: @Sendable (URLRequest) -> (Int, Data)]

    public init(_ routes: [String: @Sendable (URLRequest) -> (Int, Data)]) { self.routes = routes }

    public func handle(_ request: URLRequest, base: String) -> (Int, Data) {
        let url = request.url!.absoluteString
        var path = url.hasPrefix(base) ? String(url.dropFirst(base.count)) : url
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        if let route = routes[path] { return route(request) }
        return (404, Data("{\"error\":\"not_found\"}".utf8))
    }
}
