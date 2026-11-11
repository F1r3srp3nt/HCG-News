#if DEBUG
import SwiftUI
import NewsCore
import NewsAppModel
import HCGConnect
import HCGTransport
import Newsroom

// DEBUG-ONLY DEVELOPMENT FIXTURES for previews and UI tests.
//
// - Compiled out of Release builds.
// - Active in a running app only when launched with HCGNEWS_UI_TEST_FIXTURES=1; an
//   orange "DEVELOPMENT FIXTURES — not live reporting" banner is then shown everywhere.
// - Stored in a separate folder (Application Support/HCGNews-DevFixtures), so fixture
//   bookmarks, downloads and drafts never mix with real user data.
// - All text is fictional placeholder copy naming no real people, parties or events.
// - Never used as a fallback when live requests fail.

@MainActor
enum UITestFixtures {
    static func containerIfRequested() -> AppContainer? {
        let env = ProcessInfo.processInfo.environment
        guard env["HCGNEWS_UI_TEST_FIXTURES"] == "1" else { return nil }
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let root = support.appendingPathComponent("HCGNews-DevFixtures", isDirectory: true)
        if env["HCGNEWS_UI_TEST_RESET"] == "1" { try? FileManager.default.removeItem(at: root) }
        return PreviewFixtures.container(root: root,
                                         offline: env["HCGNEWS_UI_TEST_OFFLINE"] == "1",
                                         emptyHome: env["HCGNEWS_UI_TEST_EMPTY"] == "1")
    }
}

enum PreviewFixtures {
    @MainActor
    static func container(root: URL? = nil, offline: Bool = false, emptyHome: Bool = false) -> AppContainer {
        let root = root ?? FileManager.default.temporaryDirectory.appendingPathComponent("hcgnews-preview-\(UUID().uuidString)")
        let platform = PlatformServices(transport: FixtureTransport(), browser: NoBrowser(), sessionStore: NoSessionStore(),
                                        userAgent: "HCGNews-Fixtures", redirectScheme: "com.hakmicapitalgroup.hcgnews", appVersion: "fixtures")
        let stores = LocalStores.rooted(at: root, bundledConfiguration: nil, redirectScheme: platform.redirectScheme)
        let configuration = NewsContentConfiguration(
            contractVersion: "1", environment: "development-fixtures",
            apiBaseURL: URL(string: "https://news.hakmicapitalgroup.com/development-fixtures/")!,
            publicationURL: URL(string: "https://news.hakmicapitalgroup.com")!, approvedByFounder: true)
        let coordinator = HCGConnectCoordinator(configuration: .awaitingSetup, browser: NoBrowser(), store: NoSessionStore(),
                                                transport: FixtureTransport(), userAgent: "fixtures")
        let environment = NewsAppEnvironment(
            publication: (.ready(configuration), .bundled), connect: (.awaitingSetup, .none),
            service: FixtureNewsService(offline: offline, emptyHome: emptyHome),
            newsroomService: UnavailableNewsroomService(), newsroomServiceConfigured: false,
            coordinator: coordinator, stores: stores, transport: FixtureTransport(), appVersion: "fixtures",
            isUsingTestFixtures: true)
        return AppContainer(fixedEnvironment: environment, platform: platform, stores: stores)
    }

    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    static let sections: [NewsSection] = [
        NewsSection(id: "fx-1", slug: "fixture-politics", name: "Politics (fixture)", position: 1),
        NewsSection(id: "fx-2", slug: "fixture-norwegian-politics", name: "Norwegian Politics (fixture)", parentSlug: "fixture-politics", position: 2),
        NewsSection(id: "fx-3", slug: "fixture-international-politics", name: "International Politics (fixture)", parentSlug: "fixture-politics", position: 3),
        NewsSection(id: "fx-4", slug: "fixture-business", name: "Business (fixture)", position: 4),
        NewsSection(id: "fx-5", slug: "fixture-empty", name: "Empty Section (fixture)", description: "Used to test the empty state.", position: 5),
        NewsSection(id: "fx-6", slug: "fixture-unknown-child", name: "Orphan Section (fixture)", parentSlug: "not-in-list", position: 6),
    ]

    static let author = Author(
        id: "fixture-author-1", name: "Fixture Author", title: "Test byline",
        disclosures: [AuthorDisclosure(id: "fixture-disclosure-1", authorID: "fixture-author-1",
                                       text: "Fixture disclosure. In production this text comes verbatim from the publication's backend for the verified author.")])

    static func summary(_ n: Int, type: EditorialType = .news, breaking: Bool = false, featured: Bool = false,
                        restricted: Bool = false, headline: String? = nil, image: Bool = true, authors: [Author]? = nil) -> ArticleSummary {
        let s = sections[n % 4]
        return ArticleSummary(
            id: ArticleID("fixture-\(n)"), slug: "fixture-\(n)",
            canonicalURL: URL(string: "https://news.hakmicapitalgroup.com/development-fixtures/fixture-\(n)"),
            headline: headline ?? "Fixture headline \(n): placeholder text for layout testing",
            standfirst: "Fixture standfirst \(n). Placeholder copy used only to test wrapping, spacing and truncation.",
            section: s.ref, editorialType: type,
            authors: authors ?? [Author(id: "fixture-author-\(n % 3 + 2)", name: "Fixture Writer \(n % 3 + 1)")],
            publishedAt: base.addingTimeInterval(-Double(n) * 3600),
            updatedAt: n == 1 ? base.addingTimeInterval(-600) : nil,
            image: image ? ArticleImage(url: URL(string: "https://fixture-images.invalid/\(n).jpg")!, width: 1600,
                                        height: n.isMultiple(of: 2) ? 900 : 1600, alt: "Fixture image \(n)",
                                        caption: "Fixture caption \(n).", credit: "Fixture credit") : nil,
            isFeatured: featured,
            breaking: breaking ? BreakingFlag(active: true, label: "Breaking") : nil,
            access: restricted ? .restricted : .public, status: "published", revision: "1")
    }

    static let longHeadline = "Fixture long headline: an intentionally very long title that keeps going across several lines so that wrapping, Dynamic Type at accessibility sizes and narrow Split View widths can be checked without clipping or horizontal overflow"

    static var featured: [ArticleSummary] {
        [summary(1, type: .analysis, featured: true, headline: longHeadline, authors: [author])]
    }

    static var breaking: [ArticleSummary] {
        [summary(2, breaking: true), summary(3, breaking: true, headline: "Fixture breaking headline two")]
    }

    static var latest: [ArticleSummary] {
        (2...14).map { n in
            let types: [EditorialType] = [.news, .analysis, .opinion, .sponsored, .announcement]
            return summary(n, type: types[n % 5], breaking: n == 2 || n == 3, restricted: n == 7, image: n % 4 != 0)
        }
    }

    static func article(_ s: ArticleSummary) -> Article {
        let number = Int(s.id.rawValue.split(separator: "-").last ?? "0") ?? 0
        if number == 11 {
            return Article(summary: s, blocks: [], completeness: .summaryOnly)
        }
        return Article(summary: s, blocks: [
            .paragraph(InlineText([InlineRun("Fixture paragraph with "), InlineRun("bold", bold: true), InlineRun(", "),
                                   InlineRun("italic", italic: true), InlineRun(" and a "),
                                   InlineRun("source link", link: URL(string: "https://example.org/fixture-source")),
                                   InlineRun(". Placeholder copy for layout testing.")])),
            .heading(level: 2, text: InlineText(plain: "Fixture subheading")),
            .list(ordered: false, items: [ListItem(text: InlineText(plain: "First fixture point")),
                                          ListItem(text: InlineText(plain: "Nested fixture point"), level: 1),
                                          ListItem(text: InlineText(plain: "Second fixture point"))]),
            .quote(paragraphs: [InlineText(plain: "A fixture quotation used to test quote styling.")], attribution: "Fixture Speaker"),
            .image(ArticleImage(url: URL(string: "https://fixture-images.invalid/body.jpg")!, width: 1200, height: 800,
                                alt: "Fixture body image", caption: "Fixture body caption.", credit: "Fixture credit")),
            .embedNotice(host: "video.example.com"),
            .unsupported(type: "fixture-poll"),
            .divider,
            .paragraph(InlineText(plain: "Closing fixture paragraph.")),
        ],
        sources: [ArticleSource(title: "Fixture source document", url: URL(string: "https://example.org/fixture-report"), publisher: "Example Publisher")],
        corrections: number == 1 ? [ArticleCorrection(id: "fc1", text: "Fixture correction: a date in this placeholder article was corrected.", issuedAt: base)] : [],
        sponsor: s.editorialType == .sponsored ? SponsorNotice(sponsorName: "Fixture Partner", text: nil, url: nil) : nil,
        related: number == 1 ? [summary(4), summary(5)] : [])
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
        return NewsCapabilities(serverSearch: false, fullContent: true)
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

    func search(query: String, filters: SearchFilters, cursor: String?) async throws -> ArticlePage {
        throw NewsServiceError.contractMismatch("Server search is not offered by fixtures.")
    }
}

/// No network for fixtures: image downloads fail, which exercises "image unavailable offline".
struct FixtureTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw TransportError.offline }
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

// MARK: - Previews

@MainActor
private func previewRoot<V: View>(_ container: AppContainer, @ViewBuilder _ content: () -> V) -> some View {
    content()
        .environment(container)
        .environment(container.environment)
        .environment(Router())
        .hcgThemed()
}

#Preview("Home") {
    let container = PreviewFixtures.container()
    return previewRoot(container) { NavigationStack { HomeView().newsDestinations() } }
}

#Preview("Article") {
    let container = PreviewFixtures.container()
    return previewRoot(container) { NavigationStack { ArticleScreen(id: ArticleID("fixture-1")) } }
}

#Preview("Root – adaptive") {
    let container = PreviewFixtures.container()
    return previewRoot(container) { RootView() }
}

#Preview("Newsroom") {
    let container = PreviewFixtures.container()
    return previewRoot(container) { NewsroomWorkspace() }
}
#endif
