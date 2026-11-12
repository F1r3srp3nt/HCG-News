import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport

/// Client for the PROPOSED HCG News Content API v1.
///
/// Status: the paths and shapes below are a proposal for the owner of
/// news.hakmicapitalgroup.com (docs/HCG-NEWS-CONTENT-API-PROPOSAL.md). This client
/// is only constructed when an approved configuration is installed, and it first
/// checks the server's `contractVersion` before decoding anything else.
///
/// Public content is requested anonymously. A bearer token is attached only when
/// the server answers that an article is restricted and the reader is signed in.
public actor NewsAPIClient: NewsService {
    public typealias AccessTokenProvider = @Sendable () async -> String?

    private let configuration: NewsContentConfiguration
    private let transport: HTTPTransport
    private let userAgent: String
    private let accessToken: AccessTokenProvider
    private let now: @Sendable () -> Date
    private var meta: MetaResponse?

    public init(configuration: NewsContentConfiguration,
                transport: HTTPTransport,
                userAgent: String,
                accessToken: @escaping AccessTokenProvider = { nil },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration
        self.transport = transport
        self.userAgent = userAgent
        self.accessToken = accessToken
        self.now = now
    }

    // MARK: NewsService

    public func capabilities() async throws -> NewsCapabilities {
        let meta = try await ensureMeta()
        let filters = Set((meta.capabilities?.searchFilters ?? []).compactMap(SearchFilterKind.init(rawValue:)))
        return NewsCapabilities(serverSearch: meta.capabilities?.search ?? false,
                                serverSearchFilters: filters,
                                fullContent: meta.capabilities?.fullContent ?? true)
    }

    public func verifyConnection() async throws -> NewsCapabilities {
        meta = nil
        return try await capabilities()
    }

    public func home() async throws -> HomeFeed {
        _ = try await ensureMeta()
        let response: HomeResponse = try await get("home")
        let date = now()
        let latest = PublicationVisibility.filter(response.latest.items, now: date)
        return HomeFeed(
            featured: PublicationVisibility.filter(response.featured ?? [], now: date).filter(\.isFeatured),
            breaking: BreakingNewsRule.select(from: [response.breaking ?? [], latest], now: date),
            latest: ArticlePage(items: latest, nextCursor: response.latest.nextCursor))
    }

    public func sections() async throws -> [NewsSection] {
        _ = try await ensureMeta()
        let response: SectionsResponse = try await get("sections")
        return response.sections.sorted {
            ($0.position ?? Int.max, $0.name) < ($1.position ?? Int.max, $1.name)
        }
    }

    public func articles(sectionSlug: String?, cursor: String?) async throws -> ArticlePage {
        _ = try await ensureMeta()
        var query: [URLQueryItem] = []
        if let sectionSlug { query.append(URLQueryItem(name: "section", value: sectionSlug)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response: PageResponse = try await get("articles", query: query)
        return ArticlePage(items: PublicationVisibility.filter(response.items, now: now()), nextCursor: response.nextCursor)
    }

    public func article(id: ArticleID) async throws -> Article {
        _ = try await ensureMeta()
        let path = "articles/" + Self.pathComponent(id.rawValue)
        let response: ArticleResponse
        do {
            response = try await get(path)
        } catch NewsServiceError.restricted {
            // Retry once with the signed-in reader's token, if any.
            guard let token = await accessToken() else { throw NewsServiceError.restricted }
            response = try await get(path, bearer: token)
        }
        switch PublicationVisibility.decision(for: response.summary, now: now()) {
        case .hidden: throw NewsServiceError.notFound
        case .visible, .restricted: break
        }
        guard response.summary.id == id else {
            throw NewsServiceError.contractMismatch("Article id in response does not match the request.")
        }
        return response.article(baseURL: configuration.publicationURL)
    }

    public func search(query: String, filters: SearchFilters, cursor: String?) async throws -> ArticlePage {
        let caps = try await capabilities()
        guard caps.serverSearch else { throw NewsServiceError.contractMismatch("Server search is not offered.") }
        var items = [URLQueryItem(name: "q", value: query)]
        // Only filters the server declared are sent; the caller applies the rest locally.
        if caps.serverSearchFilters.contains(.section), let slug = filters.sectionSlug {
            items.append(URLQueryItem(name: "section", value: slug))
        }
        if caps.serverSearchFilters.contains(.type), let type = filters.editorialType {
            items.append(URLQueryItem(name: "type", value: type.wireValue))
        }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response: PageResponse = try await get("search", query: items)
        return ArticlePage(items: PublicationVisibility.filter(response.items, now: now()), nextCursor: response.nextCursor)
    }

    // MARK: Internals

    private func ensureMeta() async throws -> MetaResponse {
        if let meta { return meta }
        let fetched: MetaResponse = try await get("meta")
        guard fetched.contractVersion == configuration.contractVersion else {
            throw NewsServiceError.unsupportedContractVersion(fetched.contractVersion)
        }
        meta = fetched
        return fetched
    }

    static func pathComponent(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    func makeRequest(_ path: String, query: [URLQueryItem] = [], bearer: String? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: configuration.apiBaseURL)?.absoluteURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw NewsServiceError.other("Invalid request URL") }
        if !query.isEmpty { components.queryItems = query }
        guard let finalURL = components.url, HCGHostPolicy.isTrustedHCGURL(finalURL) else {
            throw NewsServiceError.other("Refusing to call a non-HCG host")
        }
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], bearer: String? = nil) async throws -> T {
        let request = try makeRequest(path, query: query, bearer: bearer)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as TransportError {
            switch error {
            case .offline: throw NewsServiceError.offline
            case .timedOut: throw NewsServiceError.timedOut
            case .insecureConnection: throw NewsServiceError.other("Secure connection failed")
            case .invalidResponse: throw NewsServiceError.contractMismatch("Not an HTTP response")
            case .other(let description): throw NewsServiceError.other(description)
            }
        }
        switch response.statusCode {
        case 200..<300:
            do {
                return try HCGJSON.makeDecoder().decode(T.self, from: data)
            } catch {
                throw NewsServiceError.contractMismatch(Self.describe(error))
            }
        case 401:
            throw bearer == nil ? NewsServiceError.restricted : NewsServiceError.forbidden
        case 403:
            let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            if bearer == nil, body?.error == "restricted" { throw NewsServiceError.restricted }
            throw NewsServiceError.forbidden
        case 404, 410:
            throw NewsServiceError.notFound
        case 429:
            throw NewsServiceError.rateLimited
        case 502, 503, 504:
            throw NewsServiceError.unavailable
        default:
            throw NewsServiceError.server(status: response.statusCode)
        }
    }

    /// Decoding error description without echoing response content.
    static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return "Unreadable response" }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "Missing field \(path(context).isEmpty ? "" : path(context) + ".")\(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "Unexpected value at \(path(context).isEmpty ? "root" : path(context))"
        @unknown default:
            return "Unreadable response"
        }
    }
}
