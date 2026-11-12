import Foundation
import HCGTransport
import NewsCore

/// The publication's public content, read the way the HCG News site's data is stored:
/// the `news_articles`, `news_categories` and `news_authors` tables in the shared HCG
/// project, as the anonymous role with the public client key.
///
/// What a reader can see is decided by the server (row-level security). The app also
/// asks only for published rows whose publication time has passed, asks only for
/// columns meant for readers (never `created_by`, SEO fields, view counts or notes),
/// and re-checks every row with `PublicationVisibility` before showing it.
public struct PublicationContentService: NewsService {
    public static let pageSize = 20

    /// Reader-facing article columns. Editorial metadata is never requested.
    static let summaryColumns = [
        "id", "title", "subtitle", "slug", "excerpt", "status", "content_type", "published_at", "updated_at",
        "featured_image_url", "featured_image_alt", "featured_image_caption", "featured_image_credit",
        "is_featured", "is_breaking", "is_demo", "reading_time",
        "category:news_categories(id,name,slug)", "author:news_authors(id,name,slug,title)",
    ].joined(separator: ",")
    static let articleColumns = summaryColumns + ",body,sources,correction_notes"

    let client: PlatformClient
    let now: @Sendable () -> Date
    private let sectionCache = SectionCache()

    public init(client: PlatformClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    var configuration: HCGPlatformConfiguration { client.configuration }

    // MARK: NewsService

    public func capabilities() async throws -> NewsCapabilities {
        NewsCapabilities(serverSearch: true, serverSearchFilters: [.section, .type], fullContent: true)
    }

    /// A real round trip: reads one published article id and the visible sections.
    public func verifyConnection() async throws -> NewsCapabilities {
        do {
            _ = try await client.rows(client.restRequest("news_articles", query: publishedFilter() + [
                URLQueryItem(name: "select", value: "id"), URLQueryItem(name: "limit", value: "1"),
            ], token: nil))
        } catch let error as PlatformError { throw Self.map(error) }
        return try await capabilities()
    }

    public func home() async throws -> HomeFeed {
        async let featured = list(extra: [URLQueryItem(name: "is_featured", value: "eq.true")], limit: 6)
        async let breaking = list(extra: [URLQueryItem(name: "is_breaking", value: "eq.true"),
                                          URLQueryItem(name: "is_demo", value: "is.false")], limit: BreakingNewsRule.maximumItems)
        async let latest = articles(sectionSlug: nil, cursor: nil)
        return HomeFeed(featured: try await featured.items, breaking: try await breaking.items, latest: try await latest)
    }

    public func sections() async throws -> [NewsSection] {
        let rows: [[String: Any]]
        do {
            rows = try await client.rows(client.restRequest("news_categories", query: [
                URLQueryItem(name: "select", value: "id,name,slug,description,sort_order"),
                URLQueryItem(name: "is_visible", value: "eq.true"),
                URLQueryItem(name: "order", value: "sort_order.asc.nullslast,name.asc"),
            ], token: nil))
        } catch let error as PlatformError { throw Self.map(error) }
        let sections = rows.map(Row.init).compactMap { row -> NewsSection? in
            guard let id = row.string("id"), let slug = row.nonEmpty("slug"), let name = row.nonEmpty("name") else { return nil }
            return NewsSection(id: id, slug: slug, name: name, description: row.nonEmpty("description"),
                               parentSlug: nil, position: row.int("sort_order"))
        }
        await sectionCache.store(sections)
        return sections
    }

    public func articles(sectionSlug: String?, cursor: String?) async throws -> ArticlePage {
        var extra: [URLQueryItem] = []
        if let sectionSlug {
            guard let id = try await sectionID(for: sectionSlug) else { return ArticlePage(items: [], nextCursor: nil) }
            extra.append(URLQueryItem(name: "category_id", value: "eq.\(id)"))
        }
        return try await list(extra: extra, limit: Self.pageSize, cursor: cursor)
    }

    public func article(id: ArticleID) async throws -> Article {
        guard UUID(uuidString: id.rawValue) != nil else { throw NewsServiceError.notFound }
        let rows: [[String: Any]]
        do {
            rows = try await client.rows(client.restRequest("news_articles", query: publishedFilter() + [
                URLQueryItem(name: "select", value: Self.articleColumns),
                URLQueryItem(name: "id", value: "eq.\(id.rawValue)"),
                URLQueryItem(name: "limit", value: "1"),
            ], token: nil))
        } catch let error as PlatformError { throw Self.map(error) }
        guard let row = rows.first.map(Row.init),
              let summary = PublicationMapping.summary(row, publicationURL: configuration.publicationURL),
              PublicationVisibility.decision(for: summary, now: now()) == .visible
        else { throw NewsServiceError.notFound }
        return PublicationMapping.article(row, summary: summary, publicationURL: configuration.publicationURL)
    }

    public func search(query: String, filters: SearchFilters, cursor: String?) async throws -> ArticlePage {
        let pattern = Self.searchPattern(query)
        guard !pattern.isEmpty else { return ArticlePage(items: [], nextCursor: nil) }
        var extra = [URLQueryItem(name: "or", value: "(title.ilike.\(pattern),subtitle.ilike.\(pattern),excerpt.ilike.\(pattern))")]
        if let slug = filters.sectionSlug {
            guard let id = try await sectionID(for: slug) else { return ArticlePage(items: [], nextCursor: nil) }
            extra.append(URLQueryItem(name: "category_id", value: "eq.\(id)"))
        }
        if let type = filters.editorialType {
            extra.append(URLQueryItem(name: "content_type", value: "eq.\(PublicationMapping.wireContentType(type))"))
        }
        return try await list(extra: extra, limit: Self.pageSize, cursor: cursor)
    }

    // MARK: Helpers

    /// Only published rows whose publication time has passed. The server's row-level
    /// security is the authority; this keeps the request itself unambiguous.
    func publishedFilter() -> [URLQueryItem] {
        [URLQueryItem(name: "status", value: "eq.published"),
         URLQueryItem(name: "published_at", value: "lte.\(HCGJSON.formatDate(now()))")]
    }

    func list(extra: [URLQueryItem], limit: Int, cursor: String? = nil) async throws -> ArticlePage {
        let offset = cursor.flatMap(Self.offset(from:)) ?? 0
        if cursor != nil, Self.offset(from: cursor!) == nil { throw NewsServiceError.contractMismatch("unknown cursor") }
        let rows: [[String: Any]]
        do {
            rows = try await client.rows(client.restRequest("news_articles", query: publishedFilter() + extra + [
                URLQueryItem(name: "select", value: Self.summaryColumns),
                URLQueryItem(name: "order", value: "published_at.desc,id.desc"),
                URLQueryItem(name: "limit", value: String(limit + 1)),
                URLQueryItem(name: "offset", value: String(offset)),
            ], token: nil))
        } catch let error as PlatformError { throw Self.map(error) }
        let hasMore = rows.count > limit
        let summaries = rows.prefix(limit).map(Row.init).compactMap {
            PublicationMapping.summary($0, publicationURL: configuration.publicationURL)
        }
        let visible = PublicationVisibility.filter(summaries, now: now())
        return ArticlePage(items: visible, nextCursor: hasMore ? "offset:\(offset + limit)" : nil)
    }

    static func offset(from cursor: String) -> Int? {
        guard cursor.hasPrefix("offset:"), let n = Int(cursor.dropFirst(7)), n >= 0, n < 100_000 else { return nil }
        return n
    }

    func sectionID(for slug: String) async throws -> String? {
        if let id = await sectionCache.id(for: slug) { return id }
        _ = try await sections()
        return await sectionCache.id(for: slug)
    }

    /// A PostgREST `ilike` pattern for free text. Wildcards and quoting characters typed by
    /// the reader are removed; the value is double-quoted so commas and parentheses are literal.
    static func searchPattern(_ query: String) -> String {
        let cleaned = query
            .replacingOccurrences(of: "\\", with: " ")
            .replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: "*", with: " ")
            .replacingOccurrences(of: "%", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !cleaned.isEmpty else { return "" }
        return "\"*\(cleaned.prefix(120))*\""
    }

    static func map(_ error: PlatformError) -> NewsServiceError {
        switch error {
        case .offline: .offline
        case .timedOut: .timedOut
        case .unauthorized: .restricted
        case .forbidden: .forbidden
        case .notFound: .notFound
        case .rateLimited: .rateLimited
        case .unavailable: .unavailable
        case .contract(let detail): .contractMismatch(detail)
        case .server(let status, _): .server(status: status)
        case .conflict: .server(status: 409)
        case .insecureConnection: .other("The secure connection to HCG failed.")
        case .other(let detail): .other(detail)
        }
    }
}

actor SectionCache {
    private var bySlug: [String: String] = [:]
    func store(_ sections: [NewsSection]) { bySlug = Dictionary(sections.map { ($0.slug, $0.id) }, uniquingKeysWith: { a, _ in a }) }
    func id(for slug: String) -> String? { bySlug[slug] }
}

/// Maps publication rows to the reader's models.
public enum PublicationMapping {
    static func summary(_ row: Row, publicationURL: URL) -> ArticleSummary? {
        guard let id = row.string("id"), let title = row.nonEmpty("title") else { return nil }
        let category = row.embedded("category")
        let section: SectionRef? = category.flatMap { c in
            guard let cid = c.string("id"), let slug = c.nonEmpty("slug"), let name = c.nonEmpty("name") else { return nil }
            return SectionRef(id: cid, slug: slug, name: name)
        }
        var authors: [Author] = []
        if let a = row.embedded("author"), let aid = a.string("id"), let name = a.nonEmpty("name") {
            authors = [Author(id: aid, name: name, title: a.nonEmpty("title"),
                              disclosures: PublicationDisclosures.disclosures(forAuthorID: aid))]
        }
        let image: ArticleImage? = row.nonEmpty("featured_image_url").flatMap { LinkPolicy.resolveImage($0, base: publicationURL) }.map {
            ArticleImage(url: $0, alt: row.nonEmpty("featured_image_alt"), caption: row.nonEmpty("featured_image_caption"),
                         credit: row.nonEmpty("featured_image_credit"))
        }
        let slug = row.nonEmpty("slug")
        let isDemo = row.bool("is_demo")
        return ArticleSummary(
            id: ArticleID(id), slug: slug,
            canonicalURL: slug.flatMap { canonicalURL(publicationURL: publicationURL, sectionSlug: section?.slug, slug: $0) },
            headline: title,
            standfirst: row.nonEmpty("excerpt") ?? row.nonEmpty("subtitle"),
            section: section,
            editorialType: row.nonEmpty("content_type").map(EditorialType.init(rawValue:)),
            authors: authors,
            publishedAt: row.date("published_at"),
            updatedAt: row.date("updated_at"),
            image: image,
            isFeatured: row.bool("is_featured"),
            breaking: row.bool("is_breaking") && !isDemo ? BreakingFlag(active: true) : nil,
            access: .public,
            status: row.string("status") ?? "unknown",
            revision: row.string("updated_at"),
            isDemo: isDemo)
    }

    static func article(_ row: Row, summary: ArticleSummary, publicationURL: URL) -> Article {
        let parser = HTMLContentParser(baseURL: publicationURL)
        var blocks = row.string("body").map(parser.parse) ?? []
        if let subtitle = row.nonEmpty("subtitle"), subtitle != summary.standfirst {
            blocks.insert(.paragraph(InlineText([InlineRun(subtitle, italic: true)])), at: 0)
        }
        let sources: [ArticleSource] = (row.string("sources") ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                let url = line.split(separator: " ").lazy.compactMap { URL(string: String($0)) }
                    .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil }
                return ArticleSource(title: line, url: url)
            }
        let corrections: [ArticleCorrection] = row.nonEmpty("correction_notes").map {
            [ArticleCorrection(id: "correction-\(summary.id.rawValue)", text: $0, issuedAt: nil)]
        } ?? []
        return Article(summary: summary, blocks: blocks, sources: sources, corrections: corrections,
                       completeness: blocks.isEmpty ? .summaryOnly : .full)
    }

    /// The publication's own URL scheme: `/<section slug, or "news">/<article slug>`.
    public static func canonicalURL(publicationURL: URL, sectionSlug: String?, slug: String) -> URL? {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard let s = slug.addingPercentEncoding(withAllowedCharacters: safe),
              let c = (sectionSlug ?? "news").addingPercentEncoding(withAllowedCharacters: safe) else { return nil }
        return publicationURL.appendingPathComponent(c).appendingPathComponent(s)
    }

    static func wireContentType(_ type: EditorialType) -> String {
        switch type.wireValue {
        case "commentary": "opinion"
        default: type.wireValue
        }
    }
}

/// The publication's author disclosures.
///
/// The HCG News website does not store these in the database: its `disclosures`
/// module attaches them to the author record below. They are mirrored here word for
/// word so the app shows exactly what the publication shows. If HCG moves
/// disclosures into the database, this list should be replaced by that data.
public enum PublicationDisclosures {
    public static let founderAuthorID = "d1aa3180-b73e-4a74-8757-2e464f0b2bf1"
    public static let founderAuthorDisclosure =
        "Author disclosure: Yasin Ludvigsen Hakmi is a politician affiliated with FrP and FpU."
    /// Shown on the publication's About and disclosure pages.
    public static let publicationDisclosure =
        "Political affiliation disclosure: HCG News founder and author Yasin Ludvigsen Hakmi is a politician affiliated with Fremskrittspartiet (FrP) and Fremskrittspartiets Ungdom (FpU)."

    public static func disclosures(forAuthorID id: String) -> [AuthorDisclosure] {
        guard id.lowercased() == founderAuthorID else { return [] }
        return [AuthorDisclosure(id: "political-affiliation-\(id)", authorID: id, text: founderAuthorDisclosure, kind: "political")]
    }
}
