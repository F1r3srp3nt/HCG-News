#if DEBUG
import SwiftUI
import NewsCore
import NewsAppModel
import HCGConnect
import HCGTransport

// DEBUG-ONLY FIXTURES for SwiftUI previews and UI tests.
//
// - Compiled out of Release builds (#if DEBUG).
// - Active in a running app only when launched with HCGNEWS_UI_TEST_FIXTURES=1
//   (set by the UI tests), and then an orange "TEST FIXTURES — not live reporting"
//   banner is shown on every screen.
// - All text is fictional placeholder copy. It names no real people, parties or
//   events and must never be presented as HCG News reporting.

@MainActor
enum UITestFixtures {
    static func environmentIfRequested() -> NewsAppEnvironment? {
        let env = ProcessInfo.processInfo.environment
        guard env["HCGNEWS_UI_TEST_FIXTURES"] == "1" else { return nil }
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let bookmarks = support.appendingPathComponent("HCGNews-UITest", isDirectory: true)
            .appendingPathComponent("bookmarks.json")
        if env["HCGNEWS_UI_TEST_RESET"] == "1" {
            try? FileManager.default.removeItem(at: bookmarks)
        }
        return PreviewFixtures.environment(offline: env["HCGNEWS_UI_TEST_OFFLINE"] == "1",
                                           emptyHome: env["HCGNEWS_UI_TEST_EMPTY"] == "1",
                                           bookmarkURL: bookmarks)
    }
}

enum PreviewFixtures {
    @MainActor
    static func environment(offline: Bool = false, emptyHome: Bool = false, bookmarkURL: URL? = nil) -> NewsAppEnvironment {
        let url = bookmarkURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("hcgnews-preview-\(UUID().uuidString).json")
        let configuration = NewsContentConfiguration(
            contractVersion: "1", environment: "test-fixtures",
            apiBaseURL: URL(string: "https://news.hakmicapitalgroup.com/test-fixtures/")!,
            publicationURL: URL(string: "https://news.hakmicapitalgroup.com")!,
            approvedByFounder: true)
        let coordinator = HCGConnectCoordinator(
            configuration: .awaitingSetup, browser: NoBrowser(), store: NoSessionStore(),
            transport: NoTransport(), userAgent: "HCGNews-Fixtures")
        return NewsAppEnvironment(
            contentConfiguration: .ready(configuration),
            service: FixtureNewsService(offline: offline, emptyHome: emptyHome),
            bookmarks: BookmarkStore(fileURL: url),
            connect: coordinator,
            isUsingTestFixtures: true)
    }

    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    static let sections: [NewsSection] = [
        NewsSection(id: "fx-1", slug: "fixture-politics", name: "Politics (fixture)", position: 1),
        NewsSection(id: "fx-2", slug: "fixture-norwegian-politics", name: "Norwegian Politics (fixture)", parentSlug: "fixture-politics", position: 2),
        NewsSection(id: "fx-3", slug: "fixture-international-politics", name: "International Politics (fixture)", parentSlug: "fixture-politics", position: 3),
        NewsSection(id: "fx-4", slug: "fixture-business", name: "Business (fixture)", position: 4),
        NewsSection(id: "fx-5", slug: "fixture-empty", name: "Empty Section (fixture)", description: "Used to test the empty state.", position: 5),
    ]

    static let author = Author(
        id: "fixture-author-1", name: "Fixture Author", title: "Test byline",
        disclosures: [AuthorDisclosure(id: "fixture-disclosure-1", authorID: "fixture-author-1",
                                       text: "Fixture disclosure. In production this text comes verbatim from the publication's backend for the verified author.")])

    static func summary(_ n: Int, type: EditorialType = .news, section: NewsSection? = nil, breaking: Bool = false,
                        featured: Bool = false, restricted: Bool = false, headline: String? = nil,
                        image: Bool = true, authors: [Author]? = nil) -> ArticleSummary {
        let s = section ?? sections[n % 4]
        return ArticleSummary(
            id: ArticleID("fixture-\(n)"),
            slug: "fixture-\(n)",
            canonicalURL: URL(string: "https://news.hakmicapitalgroup.com/test-fixtures/fixture-\(n)"),
            headline: headline ?? "Fixture headline \(n): placeholder text for layout testing",
            standfirst: "Fixture standfirst \(n). Placeholder copy used only to test wrapping, spacing and truncation.",
            section: s.ref,
            editorialType: type,
            authors: authors ?? [Author(id: "fixture-author-\(n % 3 + 2)", name: "Fixture Writer \(n % 3 + 1)")],
            publishedAt: base.addingTimeInterval(-Double(n) * 3600),
            updatedAt: n == 1 ? base.addingTimeInterval(-600) : nil,
            // Images point at a non-resolvable host: this exercises the "missing image" path.
            image: image ? ArticleImage(url: URL(string: "https://fixture-images.invalid/\(n).jpg")!,
                                        width: 1600, height: n.isMultiple(of: 2) ? 900 : 1600,
                                        alt: "Fixture image \(n)", caption: "Fixture caption \(n).",
                                        credit: "Fixture credit") : nil,
            isFeatured: featured,
            breaking: breaking ? BreakingFlag(active: true, label: "Breaking") : nil,
            access: restricted ? .restricted : .public,
            status: "published")
    }

    static let longHeadline = "Fixture long headline: an intentionally very long title that keeps going across several lines so that wrapping, Dynamic Type at accessibility sizes and narrow Split View widths can be checked without clipping or horizontal overflow"

    static var featured: [ArticleSummary] {
        [summary(1, type: .analysis, featured: true, headline: longHeadline, authors: [author])]
    }

    static var breaking: [ArticleSummary] {
        [summary(2, breaking: true), summary(3, type: .news, breaking: true, headline: "Fixture breaking headline two")]
    }

    static var latest: [ArticleSummary] {
        (2...14).map { n in
            summary(n, type: [.news, .analysis, .opinion][n % 3], breaking: n == 2 || n == 3,
                    restricted: n == 7, image: n % 4 != 0)
        }
    }

    static func article(_ summary: ArticleSummary) -> Article {
        Article(summary: summary, blocks: [
            .paragraph(InlineText([InlineRun("Fixture paragraph with "), InlineRun("bold", bold: true), InlineRun(", "),
                                   InlineRun("italic", italic: true), InlineRun(" and a "),
                                   InlineRun("source link", link: URL(string: "https://example.org/fixture-source")),
                                   InlineRun(". Placeholder copy for layout testing.")])),
            .heading(level: 2, text: InlineText(plain: "Fixture subheading")),
            .list(ordered: false, items: [ListItem(text: InlineText(plain: "First fixture point")),
                                          ListItem(text: InlineText(plain: "Nested fixture point"), level: 1),
                                          ListItem(text: InlineText(plain: "Second fixture point"))]),
            .list(ordered: true, items: [ListItem(text: InlineText(plain: "Step one")), ListItem(text: InlineText(plain: "Step two"))]),
            .quote(paragraphs: [InlineText(plain: "A fixture quotation used to test quote styling.")], attribution: "Fixture Speaker"),
            .image(ArticleImage(url: URL(string: "https://fixture-images.invalid/body.jpg")!, width: 1200, height: 800,
                                alt: "Fixture body image", caption: "Fixture body caption.", credit: "Fixture credit")),
            .embedNotice(host: "video.example.com"),
            .divider,
            .paragraph(InlineText(plain: "Closing fixture paragraph.")),
        ], sources: [ArticleSource(title: "Fixture source document", url: URL(string: "https://example.org/fixture-report"), publisher: "Example Publisher")])
    }
}

/// In-memory fixture service. Never touches the network.
actor FixtureNewsService: NewsService {
    let offline: Bool
    let emptyHome: Bool

    init(offline: Bool, emptyHome: Bool) {
        self.offline = offline
        self.emptyHome = emptyHome
    }

    private func check() throws { if offline { throw NewsServiceError.offline } }

    func capabilities() async throws -> NewsCapabilities {
        try check()
        return NewsCapabilities(serverSearch: false)
    }

    func home() async throws -> HomeFeed {
        try check()
        if emptyHome { return HomeFeed(featured: [], breaking: [], latest: ArticlePage(items: [], nextCursor: nil)) }
        return HomeFeed(featured: PreviewFixtures.featured, breaking: PreviewFixtures.breaking,
                        latest: ArticlePage(items: PreviewFixtures.latest, nextCursor: nil))
    }

    func sections() async throws -> [NewsSection] {
        try check()
        return PreviewFixtures.sections
    }

    func articles(sectionSlug: String?, cursor: String?) async throws -> ArticlePage {
        try check()
        let all = PreviewFixtures.featured + PreviewFixtures.latest
        guard let sectionSlug else { return ArticlePage(items: all, nextCursor: nil) }
        return ArticlePage(items: all.filter { $0.section?.slug == sectionSlug }, nextCursor: nil)
    }

    func article(id: ArticleID) async throws -> Article {
        try check()
        let all = PreviewFixtures.featured + PreviewFixtures.latest
        guard let summary = all.first(where: { $0.id == id }) else { throw NewsServiceError.notFound }
        if summary.access == .restricted { throw NewsServiceError.restricted }
        return PreviewFixtures.article(summary)
    }

    func search(query: String, cursor: String?) async throws -> ArticlePage {
        throw NewsServiceError.contractMismatch("Server search is not offered by fixtures.")
    }
}

private struct NoBrowser: BrowserAuthenticating {
    func authenticate(url: URL, callbackScheme: String, ephemeral: Bool) async throws -> URL {
        throw BrowserAuthenticationError.cancelled
    }
}

private struct NoSessionStore: ConnectSessionStoring {
    func load() throws -> ConnectSession? { nil }
    func save(_ session: ConnectSession) throws {}
    func delete() throws {}
}

private struct NoTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw TransportError.offline }
}

// MARK: - Previews

#Preview("Home – Future, iPhone") {
    NavigationStack { HomeView().newsDestinations() }
        .environment(PreviewFixtures.environment())
        .environment(Router())
        .hcgThemed()
}

#Preview("Article – Classic") {
    NavigationStack { ArticleScreen(id: ArticleID("fixture-1")) }
        .environment(PreviewFixtures.environment())
        .environment(Router())
        .hcgThemed()
        .defaultAppStorage(UserDefaults(suiteName: "preview-classic")!)
}

#Preview("Root – adaptive") {
    RootView()
        .environment(PreviewFixtures.environment())
        .environment(Router())
        .hcgThemed()
}

#Preview("Not connected") {
    NavigationStack { HomeView() }
        .environment(NewsAppEnvironment(
            contentConfiguration: .awaitingSetup,
            service: UnconfiguredNewsService(reasons: []),
            bookmarks: BookmarkStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("p.json")),
            connect: HCGConnectCoordinator(configuration: .awaitingSetup, browser: NoBrowser(), store: NoSessionStore(),
                                           transport: NoTransport(), userAgent: "preview")))
        .environment(Router())
        .hcgThemed()
}
#endif
