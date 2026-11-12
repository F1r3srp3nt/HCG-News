import Foundation

/// Errors a news service reports. Each maps to an honest UI state.
public enum NewsServiceError: Error, Equatable, Sendable {
    /// No approved content API configuration is installed in this build.
    case notConfigured
    /// A configuration is installed but cannot be used (see the configuration problems).
    case invalidConfiguration
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
    /// The publication answered, but no published article is readable without signing in
    /// (typically: public reading isn't enabled for apps). Only reported by connection checks.
    case noPublicContent
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
    /// Forces a fresh contract check (used by "Check connection").
    func verifyConnection() async throws -> NewsCapabilities
    /// Only called when `capabilities().serverSearch` is true. Only filters in
    /// `capabilities().serverSearchFilters` are sent to the server.
    func search(query: String, filters: SearchFilters, cursor: String?) async throws -> ArticlePage
}

/// Used when no approved configuration exists. Never returns content.
public struct UnconfiguredNewsService: NewsService {
    /// Human-readable reasons the configuration is missing or invalid.
    public let reasons: [String]
    /// True when a configuration exists but is invalid (as opposed to missing).
    public let invalid: Bool

    public init(reasons: [String], invalid: Bool = false) {
        self.reasons = reasons
        self.invalid = invalid
    }

    private var error: NewsServiceError { invalid ? .invalidConfiguration : .notConfigured }

    public func capabilities() async throws -> NewsCapabilities { throw error }
    public func home() async throws -> HomeFeed { throw error }
    public func sections() async throws -> [NewsSection] { throw error }
    public func articles(sectionSlug: String?, cursor: String?) async throws -> ArticlePage { throw error }
    public func article(id: ArticleID) async throws -> Article { throw error }
    public func search(query: String, filters: SearchFilters, cursor: String?) async throws -> ArticlePage { throw error }
    public func verifyConnection() async throws -> NewsCapabilities { throw error }
}

extension NewsService {
    /// Re-checks the connection from scratch (no cached contract information).
    public func verifyConnection() async throws -> NewsCapabilities { try await capabilities() }
}
