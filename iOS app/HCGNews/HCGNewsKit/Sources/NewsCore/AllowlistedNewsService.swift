import Foundation

/// Shows only listed articles from another news service. Used for App Store screenshots
/// (DEBUG builds only), so that screenshots contain real published articles that passed
/// editorial review, and nothing else. Release builds never use it.
public struct AllowlistedNewsService: NewsService {
    public let base: NewsService
    public let allowed: Set<ArticleID>

    public init(base: NewsService, allowed: Set<ArticleID>) {
        self.base = base
        self.allowed = allowed
    }

    private func keep(_ items: [ArticleSummary]) -> [ArticleSummary] { items.filter { allowed.contains($0.id) } }
    private func keep(_ page: ArticlePage) -> ArticlePage { ArticlePage(items: keep(page.items), nextCursor: page.nextCursor) }

    public func capabilities() async throws -> NewsCapabilities { try await base.capabilities() }
    public func verifyConnection() async throws -> NewsCapabilities { try await base.verifyConnection() }
    public func home() async throws -> HomeFeed {
        let feed = try await base.home()
        return HomeFeed(featured: keep(feed.featured), breaking: keep(feed.breaking), latest: keep(feed.latest))
    }
    public func sections() async throws -> [NewsSection] { try await base.sections() }
    public func articles(sectionSlug: String?, cursor: String?) async throws -> ArticlePage {
        keep(try await base.articles(sectionSlug: sectionSlug, cursor: cursor))
    }
    public func article(id: ArticleID) async throws -> Article {
        guard allowed.contains(id) else { throw NewsServiceError.notFound }
        let article = try await base.article(id: id)
        return Article(summary: article.summary, blocks: article.blocks, sources: article.sources,
                       corrections: article.corrections, sponsor: article.sponsor, audio: article.audio,
                       related: keep(article.related), completeness: article.completeness)
    }
    public func search(query: String, filters: SearchFilters, cursor: String?) async throws -> ArticlePage {
        keep(try await base.search(query: query, filters: filters, cursor: cursor))
    }
}
