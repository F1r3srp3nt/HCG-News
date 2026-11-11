import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import HCGTestSupport
import NewsCore
import HCGConnect
@testable import NewsAppModel

// Fictional, test-only content.

/// An in-memory news service for model tests.
actor StubNewsService: NewsService {
    var homeResult: Result<HomeFeed, NewsServiceError>
    var pages: [String: Result<ArticlePage, NewsServiceError>] = [:]
    var sectionsResult: Result<[NewsSection], NewsServiceError> = .success([])
    var serverSearch = false
    var searchResult: Result<ArticlePage, NewsServiceError> = .success(ArticlePage(items: [], nextCursor: nil))
    var articleResult: Result<Article, NewsServiceError> = .failure(.notFound)

    init(home: Result<HomeFeed, NewsServiceError>) { homeResult = home }

    func setHome(_ r: Result<HomeFeed, NewsServiceError>) { homeResult = r }
    func setPage(_ cursor: String, _ r: Result<ArticlePage, NewsServiceError>) { pages[cursor] = r }
    func setSections(_ r: Result<[NewsSection], NewsServiceError>) { sectionsResult = r }
    func setServerSearch(_ v: Bool, _ r: Result<ArticlePage, NewsServiceError>) { serverSearch = v; searchResult = r }
    func setArticle(_ r: Result<Article, NewsServiceError>) { articleResult = r }

    func capabilities() async throws -> NewsCapabilities { NewsCapabilities(serverSearch: serverSearch) }
    func home() async throws -> HomeFeed { try homeResult.get() }
    func sections() async throws -> [NewsSection] { try sectionsResult.get() }
    func articles(sectionSlug: String?, cursor: String?) async throws -> ArticlePage {
        try (pages[cursor ?? "first"] ?? .success(ArticlePage(items: [], nextCursor: nil))).get()
    }
    func article(id: ArticleID) async throws -> Article { try articleResult.get() }
    func search(query: String, cursor: String?) async throws -> ArticlePage { try searchResult.get() }
}

func summary(_ id: String, headline: String? = nil, breaking: Bool = false) -> ArticleSummary {
    ArticleSummary(id: ArticleID(id), canonicalURL: URL(string: "https://news.hakmicapitalgroup.com/a/\(id)"),
                   headline: headline ?? "Fictional headline \(id)",
                   publishedAt: Date(timeIntervalSince1970: 1_790_000_000),
                   breaking: breaking ? BreakingFlag(active: true) : nil)
}

func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("hcgnews-model-\(UUID().uuidString)/bookmarks.json")
}

final class HomeModelTests: XCTestCase {
    @MainActor
    func testUnconfiguredShowsNotConnectedState() async {
        let model = HomeModel(service: UnconfiguredNewsService(reasons: []), index: LoadedArticleIndex())
        await model.loadIfNeeded()
        guard case .failed(let error) = model.state else { return XCTFail() }
        XCTAssertEqual(error.kind, .notConfigured)
        XCTAssertFalse(error.canRetry)
        XCTAssertEqual(error.title, "Live publication not connected")
    }

    @MainActor
    func testFeaturedAreNotRepeatedInLatestAndPaginationDeduplicates() async {
        let feed = HomeFeed(featured: [summary("f")], breaking: [summary("b", breaking: true)],
                            latest: ArticlePage(items: [summary("f"), summary("l1")], nextCursor: "c2"))
        let service = StubNewsService(home: .success(feed))
        await service.setPage("c2", .success(ArticlePage(items: [summary("l1"), summary("l2")], nextCursor: nil)))
        let index = LoadedArticleIndex()
        let model = HomeModel(service: service, index: index)
        await model.reload()
        XCTAssertEqual(model.state.value?.latest.map(\.id.rawValue), ["l1"])
        XCTAssertEqual(model.breaking.current?.id.rawValue, "b")
        await model.loadMore()
        XCTAssertEqual(model.state.value?.latest.map(\.id.rawValue), ["l1", "l2"])
        XCTAssertNil(model.state.value?.nextCursor)
        XCTAssertEqual(index.count, 4)
    }

    @MainActor
    func testFailedRefreshKeepsExistingContent() async {
        let feed = HomeFeed(featured: [], breaking: [], latest: ArticlePage(items: [summary("l1")], nextCursor: nil))
        let service = StubNewsService(home: .success(feed))
        let model = HomeModel(service: service, index: LoadedArticleIndex())
        await model.reload()
        await service.setHome(.failure(.offline))
        await model.reload()
        XCTAssertEqual(model.state.value?.latest.count, 1)
        XCTAssertEqual(model.loadMoreError?.kind, .offline)
    }

    func testBreakingCarouselNavigation() {
        var carousel = BreakingCarousel(items: [summary("1"), summary("2"), summary("3")])
        XCTAssertEqual(carousel.positionLabel, "1 of 3")
        carousel.previous()
        XCTAssertEqual(carousel.current?.id.rawValue, "3")
        carousel.next()
        carousel.next()
        XCTAssertEqual(carousel.current?.id.rawValue, "2")
        let refreshed = BreakingCarousel(items: [summary("9"), summary("2")], keepingCurrentFrom: carousel)
        XCTAssertEqual(refreshed.current?.id.rawValue, "2", "stays on the same headline after refresh")
        var empty = BreakingCarousel(items: [])
        empty.next()
        XCTAssertNil(empty.current)
        XCTAssertFalse(empty.hasMultiple)
    }
}

final class SectionsAndSearchTests: XCTestCase {
    func testSectionTreeFollowsBackendHierarchy() {
        let sections = [
            NewsSection(id: "1", slug: "politics", name: "Politics"),
            NewsSection(id: "2", slug: "norwegian-politics", name: "Norwegian Politics", parentSlug: "politics"),
            NewsSection(id: "3", slug: "international-politics", name: "International Politics", parentSlug: "politics"),
            NewsSection(id: "4", slug: "business", name: "Business"),
            NewsSection(id: "5", slug: "orphan", name: "Orphan", parentSlug: "missing"),
        ]
        let tree = SectionsModel.tree(sections)
        XCTAssertEqual(tree.map(\.section.slug), ["politics", "business", "orphan"])
        XCTAssertEqual(tree[0].children.map(\.name), ["Norwegian Politics", "International Politics"])
    }

    @MainActor
    func testEmptySectionsLoadAsEmpty() async {
        let service = StubNewsService(home: .failure(.offline))
        let model = SectionsModel(service: service)
        await model.reload()
        XCTAssertEqual(model.state, .loaded([]))
    }

    @MainActor
    func testSearchFallsBackToLoadedArticlesWithLabel() async {
        let service = StubNewsService(home: .failure(.offline))
        let index = LoadedArticleIndex()
        index.record([summary("1", headline: "Budget debate in Stortinget"), summary("2", headline: "Markets close higher")])
        let model = SearchModel(service: service, index: index)
        await model.search("budget")
        XCTAssertEqual(model.state.value?.scope, .loadedArticlesOnly)
        XCTAssertEqual(model.state.value?.items.map(\.id.rawValue), ["1"])
        await model.search("x")
        XCTAssertEqual(model.state, .idle, "single characters do not search")
    }

    @MainActor
    func testServerSearchIsUsedWhenOffered() async {
        let service = StubNewsService(home: .failure(.offline))
        await service.setServerSearch(true, .success(ArticlePage(items: [summary("s")], nextCursor: "n")))
        let model = SearchModel(service: service, index: LoadedArticleIndex())
        await model.search("anything")
        XCTAssertEqual(model.state.value?.scope, .publication)
        XCTAssertEqual(model.state.value?.items.count, 1)
    }

    @MainActor
    func testSearchWhenUnconfigured() async {
        let model = SearchModel(service: UnconfiguredNewsService(reasons: []), index: LoadedArticleIndex())
        await model.search("anything")
        guard case .failed(let error) = model.state else { return XCTFail() }
        XCTAssertEqual(error.kind, .notConfigured)
        await model.search("")
        guard case .failed = model.state else { return XCTFail("an empty query must not hide the not-connected state") }
    }
}

final class SavedAndArticleTests: XCTestCase {
    @MainActor
    func testSavedSurvivesRelaunchThroughModels() async {
        let url = tempURL()
        let saved = SavedModel(store: BookmarkStore(fileURL: url))
        await saved.load()
        await saved.toggle(summary("a"))
        XCTAssertTrue(saved.isSaved(ArticleID("a")))

        let relaunched = SavedModel(store: BookmarkStore(fileURL: url))
        await relaunched.load()
        XCTAssertEqual(relaunched.bookmarks.map(\.articleID.rawValue), ["a"])
        await relaunched.remove(ArticleID("a"))
        XCTAssertTrue(relaunched.bookmarks.isEmpty)
    }

    @MainActor
    func testArticleModelSavesUsingStableIDAndRefreshesSnapshot() async {
        let saved = SavedModel(store: BookmarkStore(fileURL: tempURL()))
        await saved.load()
        await saved.toggle(summary("a", headline: "Old headline"))
        let service = StubNewsService(home: .failure(.offline))
        await service.setArticle(.success(Article(summary: summary("a", headline: "Corrected headline"), blocks: [])))
        let model = ArticleModel(id: ArticleID("a"), preview: nil, service: service, saved: saved)
        await model.load()
        XCTAssertEqual(saved.bookmarks.first?.headline, "Corrected headline")
        XCTAssertTrue(model.isSaved)
        await model.toggleSaved()
        XCTAssertFalse(model.isSaved)
    }

    @MainActor
    func testUnpublishedSavedArticleShowsNotFound() async {
        let service = StubNewsService(home: .failure(.offline))
        let model = ArticleModel(id: ArticleID("gone"), preview: nil, service: service,
                                 saved: SavedModel(store: BookmarkStore(fileURL: tempURL())))
        await model.load()
        guard case .failed(let error) = model.state else { return XCTFail() }
        XCTAssertEqual(error.kind, .notFound)
    }
}

final class EnvironmentTests: XCTestCase {
    @MainActor
    func testLiveEnvironmentWithoutConfigurationMakesNoNetworkRequests() async {
        let transport = FakeTransport()
        let env = NewsAppEnvironment.live(
            configurationData: nil, expectedRedirectScheme: "com.hakmicapitalgroup.hcgnews",
            transport: transport, browser: NeverBrowser(), sessionStore: NoStore(),
            bookmarkFileURL: tempURL(), userAgent: "HCGNews-Tests")
        await env.home.loadIfNeeded()
        await env.sections.loadIfNeeded()
        await env.search.search("politics")
        await env.account.restore()
        await env.account.signIn()
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(env.contentConfiguration, .awaitingSetup)
        XCTAssertEqual(env.account.status?.authentication, .unavailable)
        XCTAssertFalse(env.account.configurationProblems.isEmpty)
        XCTAssertFalse(env.contentConfigurationProblems.isEmpty)
    }
}

struct NeverBrowser: BrowserAuthenticating {
    func authenticate(url: URL, callbackScheme: String, ephemeral: Bool) async throws -> URL {
        XCTFail("browser must not open without configuration")
        throw BrowserAuthenticationError.cancelled
    }
}

struct NoStore: ConnectSessionStoring {
    func load() throws -> ConnectSession? { nil }
    func save(_ session: ConnectSession) throws {}
    func delete() throws {}
}
