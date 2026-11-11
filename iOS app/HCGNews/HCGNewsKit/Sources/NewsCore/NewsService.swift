import Foundation

/// Errors a news service reports. Each maps to an honest UI state.
public enum NewsServiceError: Error, Equatable, Sendable {
    /// No approved content API configuration is installed in this build.
    case notConfigured
    /// Device offline or host unreachable.
    case offline
    case timedOut
    /// The article does not exist or is no longer published.
    case notFound
    /// The backend marks this content as requiring an authorised HCG sign-in.
    case restricted
    /// Signed in, but the backend refused access.
    case forbidden
    case rateLimited
    case unavailable
    /// The response did not match the agreed contract.
    case contractMismatch(String)
    /// The server's contract version is not one this app understands.
    case unsupportedContractVersion(String)
    case server(status: Int)
    case other(String)
}

/// The content source for the reader. One implementation talks to the HCG News
/// content API once a supported contract is confirmed; `UnconfiguredNewsService`
/// is used until then. There is intentionally no implementation that scrapes
/// rendered web pages.
public protocol NewsService: Sendable {
    func capabilities() async throws -> NewsCapabilities
    func home() async throws -> HomeFeed
    func sections() async throws -> [NewsSection]
    func articles(sectionSlug: String?, cursor: String?) async throws -> ArticlePage
    func article(id: ArticleID) async throws -> Article
    /// Only called when `capabilities().serverSearch` is true.
    func search(query: String, cursor: String?) async throws -> ArticlePage
}

/// Used when no approved configuration exists. Never returns content.
public struct UnconfiguredNewsService: NewsService {
    /// Human-readable reasons the configuration is missing or invalid.
    public let reasons: [String]

    public init(reasons: [String]) { self.reasons = reasons }

    public func capabilities() async throws -> NewsCapabilities { throw NewsServiceError.notConfigured }
    public func home() async throws -> HomeFeed { throw NewsServiceError.notConfigured }
    public func sections() async throws -> [NewsSection] { throw NewsServiceError.notConfigured }
    public func articles(sectionSlug: String?, cursor: String?) async throws -> ArticlePage { throw NewsServiceError.notConfigured }
    public func article(id: ArticleID) async throws -> Article { throw NewsServiceError.notConfigured }
    public func search(query: String, cursor: String?) async throws -> ArticlePage { throw NewsServiceError.notConfigured }
}
