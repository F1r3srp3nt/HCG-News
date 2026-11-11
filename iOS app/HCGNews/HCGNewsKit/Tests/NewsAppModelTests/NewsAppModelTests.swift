import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import HCGTestSupport
import NewsCore
import HCGConnect
import Newsroom
@testable import NewsAppModel

// Fixture-based tests: fictional content, fake transports and temp folders.
// None of these talk to a live HCG service.

actor StubNewsService: NewsService {
    var homeResult: Result<HomeFeed, NewsServiceError>
    var pages: [String: Result<ArticlePage, NewsServiceError>] = [:]
    var sectionsResult: Result<[NewsSection], NewsServiceError> = .success([])
    var caps = NewsCapabilities(serverSearch: false)
    var searchResult: Result<ArticlePage, NewsServiceError> = .success(ArticlePage(items: [], nextCursor: nil))
    var articleResult: Result<Article, NewsServiceError> = .failure(.notFound)
    var lastSearchFilters: SearchFilters?

    init(home: Result<HomeFeed, NewsServiceError>) { homeResult = home }

    func setHome(_ r: Result<HomeFeed, NewsServiceError>) { homeResult = r }
    func setPage(_ cursor: String, _ r: Result<ArticlePage, NewsServiceError>) { pages[cursor] = r }
    func setSections(_ r: Result<[NewsSection], NewsServiceError>) { sectionsResult = r }
    func setCapabilities(_ c: NewsCapabilities, search: Result<ArticlePage, NewsServiceError>) { caps = c; searchResult = search }
    func setArticle(_ r: Result<Article, NewsServiceError>) { articleResult = r }

    func capabilities() async throws -> NewsCapabilities { caps }
    func home() async throws -> HomeFeed { try homeResult.get() }
    func sections() async throws -> [NewsSection] { try sectionsResult.get() }
    func articles(sectionSlug: String?, cursor: String?) async throws -> ArticlePage {
        try (pages[cursor ?? "first"] ?? .success(ArticlePage(items: [], nextCursor: nil))).get()
    }
    func article(id: ArticleID) async throws -> Article { try articleResult.get() }
    func search(query: String, filters: SearchFilters, cursor: String?) async throws -> ArticlePage {
        lastSearchFilters = filters
        return try searchResult.get()
    }
}

final class MemorySessionStore: ConnectSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: ConnectSession?
    init(_ session: ConnectSession? = nil) { self.session = session }
    var current: ConnectSession? { lock.withLock { session } }
    func load() throws -> ConnectSession? { lock.withLock { session } }
    func save(_ session: ConnectSession) throws { lock.withLock { self.session = session } }
    func delete() throws { lock.withLock { session = nil } }
}

struct NeverBrowser: BrowserAuthenticating {
    func authenticate(url: URL, callbackScheme: String, ephemeral: Bool) async throws -> URL {
        throw BrowserAuthenticationError.cancelled
    }
}

func summary(_ id: String, headline: String? = nil, breaking: Bool = false, section: String? = nil,
             type: EditorialType? = nil, revision: String? = nil) -> ArticleSummary {
    ArticleSummary(id: ArticleID(id), canonicalURL: URL(string: "https://news.hakmicapitalgroup.com/a/\(id)"),
                   headline: headline ?? "Fictional headline \(id)",
                   section: section.map { SectionRef(id: $0, slug: $0, name: $0.capitalized) },
                   editorialType: type,
                   publishedAt: Date(timeIntervalSince1970: 1_790_000_000),
                   breaking: breaking ? BreakingFlag(active: true) : nil, revision: revision)
}

func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("hcgnews-model-\(UUID().uuidString)")
}

let scheme = "com.hakmicapitalgroup.hcgnews"

var publicationJSON: [String: Any] { ["content": [
    "contractVersion": "1", "environment": "beta", "approvedByFounder": true,
    "apiBaseURL": "https://news.hakmicapitalgroup.com/api/test/v1/",
    "publicationURL": "https://news.hakmicapitalgroup.com",
]] }

func connectJSON(clientID: String = "test-native-client", environment: String = "beta") -> [String: Any] {
    ["connect": [
        "contractVersion": "1", "environment": environment, "approvedByFounder": true,
        "issuer": "https://id.hakmicapitalgroup.com/auth",
        "authorizationEndpoint": "https://id.hakmicapitalgroup.com/auth/authorize",
        "tokenEndpoint": "https://id.hakmicapitalgroup.com/auth/token",
        "appAccessEndpoint": "https://beta.hakmicapitalgroup.com/api/test/app-access",
        "clientID": clientID,
        "redirectURI": "\(scheme):/oauth/callback",
        "scopes": ["openid", "profile"],
        "appIdentifier": "hcg-news-test",
    ]]
}

// MARK: - Configuration

final class ConfigurationStoreTests: XCTestCase {
    var root: URL!
    override func setUp() { root = tempRoot() }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func store(bundled: Data? = nil) -> ConfigurationStore {
        ConfigurationStore(directory: root, bundled: bundled, expectedRedirectScheme: scheme)
    }

    func testValidImportPreviewsAppliesAndPersistsAcrossLaunches() async throws {
        let s = store()
        let preview = await s.preview(JSONFixture.data(publicationJSON), as: .publication)
        XCTAssertTrue(preview.isValid)
        XCTAssertEqual(preview.environment, "beta")
        XCTAssertTrue(preview.destinations.contains { $0.contains("news.hakmicapitalgroup.com") })
        let before = await s.publicationState()
        XCTAssertEqual(before.0, .awaitingSetup, "preview changes nothing")
        try await s.apply(preview)

        let relaunched = store()
        let (state, source) = await relaunched.publicationState()
        guard case .ready(let c) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(c.environment, "beta")
        guard case .imported = source else { return XCTFail("\(source)") }
    }

    func testInvalidImportLeavesPreviousConfigurationActive() async throws {
        let s = store()
        try await s.apply(await s.preview(JSONFixture.data(publicationJSON), as: .publication))
        var bad = publicationJSON["content"] as! [String: Any]
        bad["apiBaseURL"] = "http://news.hakmicapitalgroup.com/api"
        let preview = await s.preview(JSONFixture.data(["content": bad]), as: .publication)
        XCTAssertFalse(preview.isValid)
        do { try await s.apply(preview); XCTFail() } catch {
            XCTAssertEqual(error as? ConfigurationStoreError, .invalidPreview)
        }
        let (state, _) = await s.publicationState()
        guard case .ready = state else { return XCTFail("previous configuration must stay active") }
    }

    func testSecretsAnywhereInTheFileAreRejected() async {
        var file = publicationJSON
        var connect = connectJSON()["connect"] as! [String: Any]
        connect["client_secret"] = "never"
        file["connect"] = connect
        let preview = await store().preview(JSONFixture.data(file), as: .publication)
        XCTAssertFalse(preview.isValid)
        XCTAssertTrue(preview.problems[0].contains("connect.client_secret"))
    }

    func testOtherSectionIsNotedNotImported() async {
        var both = publicationJSON
        both["connect"] = connectJSON()["connect"]
        let preview = await store().preview(JSONFixture.data(both), as: .publication)
        XCTAssertTrue(preview.isValid)
        XCTAssertEqual(preview.notes.count, 1)
    }

    func testRemovalFallsBackToBundled() async throws {
        let bundled = JSONFixture.data(publicationJSON)
        let s = store(bundled: bundled)
        var (state, source) = await s.publicationState()
        XCTAssertEqual(source, .bundled)
        var other = publicationJSON["content"] as! [String: Any]
        other["environment"] = "production"
        try await s.apply(await s.preview(JSONFixture.data(["content": other]), as: .publication))
        (state, source) = await s.publicationState()
        guard case .ready(let c) = state, case .imported = source else { return XCTFail() }
        XCTAssertEqual(c.environment, "production")
        await s.remove(.publication)
        (state, source) = await s.publicationState()
        XCTAssertEqual(source, .bundled)
        guard case .ready(let back) = state else { return XCTFail() }
        XCTAssertEqual(back.environment, "beta")
    }

    func testIdentityChangeIsDetected() async throws {
        let s = store()
        let first = try await s.apply(await s.preview(JSONFixture.data(connectJSON()), as: .connect))
        XCTAssertTrue(first.identityChanged, "none → configured is an identity change")
        let same = await s.preview(JSONFixture.data(connectJSON()), as: .connect)
        XCTAssertFalse(same.changesIdentity)
        let other = await s.preview(JSONFixture.data(connectJSON(clientID: "another-client")), as: .connect)
        XCTAssertTrue(other.changesIdentity)
        let applied = try await s.apply(other)
        XCTAssertTrue(applied.identityChanged)
    }

    func testCardXRedirectIsRejectedOnImport() async {
        var c = connectJSON()["connect"] as! [String: Any]
        c["redirectURI"] = "hcgcardx://auth/callback"
        let preview = await store().preview(JSONFixture.data(["connect": c]), as: .connect)
        XCTAssertFalse(preview.isValid)
    }
}

// MARK: - Container: identity change, public reading

final class AppContainerTests: XCTestCase {
    var root: URL!
    override func setUp() { root = tempRoot() }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    @MainActor
    func testIdentityConfigurationChangeSignsOutAndDetachesDraftLinksButKeepsWork() async throws {
        let sessionStore = MemorySessionStore()
        let platform = PlatformServices(transport: FakeTransport(), browser: NeverBrowser(), sessionStore: sessionStore,
                                        userAgent: "tests", redirectScheme: scheme, appVersion: "test")
        let stores = LocalStores.rooted(at: root, bundledConfiguration: nil, redirectScheme: scheme)
        let container = await AppContainer(platform: platform, stores: stores)
        try await container.apply(await container.preview(JSONFixture.data(connectJSON()), as: .connect))

        // A signed-in session and a linked draft exist.
        try sessionStore.save(ConnectSession(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, subject: "s",
                                             displayName: nil, environment: "beta"))
        var draft = try await stores.drafts.create()
        draft.headline = "My work"
        draft = try await stores.drafts.save(draft)
        _ = try await stores.drafts.link(draft.id, to: ServerLink(serverDraftID: "srv", serverRevision: "1", remoteStatus: "draft",
                                                                  lastSyncedAt: Date(), environment: "beta"))
        try await stores.bookmarks.save(summary("saved"))

        try await container.apply(await container.preview(JSONFixture.data(connectJSON(clientID: "different")), as: .connect))
        XCTAssertNil(sessionStore.current, "the old session must not carry over")
        let after = await stores.drafts.draft(draft.id)
        XCTAssertEqual(after?.headline, "My work")
        XCTAssertNil(after?.serverLink)
        let bookmarks = await stores.bookmarks.all()
        XCTAssertEqual(bookmarks.count, 1, "saved articles are not account data")
        XCTAssertNotNil(container.lastChangeMessage)
    }

    @MainActor
    func testPublicReadingWorksWithoutAnyIdentityConfiguration() async throws {
        let meta = JSONFixture.data(JSONFixture.meta())
        let home = JSONFixture.data(["latest": ["items": [JSONFixture.summary(id: "p1", publishedAt: Date(timeIntervalSince1970: 1_790_000_000))], "nextCursor": NSNull()]])
        let transport = FakeTransport { request in
            let path = request.url!.path
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "public reading never needs a token")
            if path.hasSuffix("/meta") { return (200, meta) }
            if path.hasSuffix("/home") { return (200, home) }
            return (404, Data())
        }
        let platform = PlatformServices(transport: transport, browser: NeverBrowser(), sessionStore: MemorySessionStore(),
                                        userAgent: "tests", redirectScheme: scheme, appVersion: "test")
        let stores = LocalStores.rooted(at: root, bundledConfiguration: JSONFixture.data(publicationJSON), redirectScheme: scheme)
        let container = await AppContainer(platform: platform, stores: stores)
        XCTAssertEqual(container.environment.connectConfiguration, .awaitingSetup)
        await container.environment.home.reload()
        XCTAssertEqual(container.environment.home.state.value?.latest.map(\.id.rawValue), ["p1"])
    }

    @MainActor
    func testUnconfiguredAndInvalidAreDistinctStates() async {
        let platform = PlatformServices(transport: FakeTransport(), browser: NeverBrowser(), sessionStore: MemorySessionStore(),
                                        userAgent: "tests", redirectScheme: scheme, appVersion: "test")
        let empty = await AppContainer(platform: platform, stores: LocalStores.rooted(at: root, bundledConfiguration: nil, redirectScheme: scheme))
        await empty.environment.home.reload()
        guard case .failed(let e1) = empty.environment.home.state else { return XCTFail() }
        XCTAssertEqual(e1.kind, .notConfigured)

        var bad = publicationJSON["content"] as! [String: Any]
        bad["approvedByFounder"] = false
        let invalid = await AppContainer(platform: platform, stores: LocalStores.rooted(at: tempRoot(), bundledConfiguration: JSONFixture.data(["content": bad]), redirectScheme: scheme))
        await invalid.environment.home.reload()
        guard case .failed(let e2) = invalid.environment.home.state else { return XCTFail() }
        XCTAssertEqual(e2.kind, .invalidConfiguration)
    }
}

// MARK: - Home, sections, search

final class HomeAndSearchTests: XCTestCase {
    @MainActor
    func testPaginationDeduplicatesAndStopsOnRepeatedCursor() async {
        let feed = HomeFeed(featured: [summary("f")], breaking: [summary("b", breaking: true)],
                            latest: ArticlePage(items: [summary("f"), summary("l1")], nextCursor: "c2"))
        let service = StubNewsService(home: .success(feed))
        await service.setPage("c2", .success(ArticlePage(items: [summary("l1"), summary("l2"), summary("f")], nextCursor: "c2")))
        let model = HomeModel(service: service, index: LoadedArticleIndex())
        await model.reload()
        XCTAssertEqual(model.state.value?.latest.map(\.id.rawValue), ["l1"])
        XCTAssertEqual(model.state.value?.lead?.id.rawValue, "f")
        XCTAssertTrue(model.state.value!.hasEditorialFeatured)
        await model.loadMore()
        XCTAssertEqual(model.state.value?.latest.map(\.id.rawValue), ["l1", "l2"])
        XCTAssertNil(model.state.value?.nextCursor, "a repeated cursor ends pagination")
    }

    @MainActor
    func testLeadWithoutEditorialFeaturedIsNewestAndNotLabelledFeatured() async {
        let feed = HomeFeed(featured: [], breaking: [], latest: ArticlePage(items: [summary("n1"), summary("n2")], nextCursor: nil))
        let model = HomeModel(service: StubNewsService(home: .success(feed)), index: LoadedArticleIndex())
        await model.reload()
        XCTAssertEqual(model.state.value?.lead?.id.rawValue, "n1")
        XCTAssertFalse(model.state.value!.hasEditorialFeatured)
    }

    @MainActor
    func testFailedRefreshKeepsContent() async {
        let service = StubNewsService(home: .success(HomeFeed(featured: [], breaking: [], latest: ArticlePage(items: [summary("l1")], nextCursor: nil))))
        let model = HomeModel(service: service, index: LoadedArticleIndex())
        await model.reload()
        await service.setHome(.failure(.offline))
        await model.reload()
        XCTAssertEqual(model.state.value?.latest.count, 1)
        XCTAssertEqual(model.refreshError?.kind, .offline)
    }

    func testBreakingCarousel() {
        var c = BreakingCarousel(items: [summary("1"), summary("2"), summary("3")])
        c.previous()
        XCTAssertEqual(c.current?.id.rawValue, "3")
        c.next(); c.next()
        XCTAssertEqual(BreakingCarousel(items: [summary("9"), summary("2")], keepingCurrentFrom: c).current?.id.rawValue, "2")
    }

    func testSectionTreeKeepsUnknownParents() {
        let tree = SectionsModel.tree([
            NewsSection(id: "1", slug: "politics", name: "Politics"),
            NewsSection(id: "2", slug: "norwegian-politics", name: "Norwegian Politics", parentSlug: "politics"),
            NewsSection(id: "5", slug: "orphan", name: "Orphan", parentSlug: "missing"),
        ])
        XCTAssertEqual(tree.map(\.section.slug), ["politics", "orphan"])
        XCTAssertEqual(tree[0].children.map(\.name), ["Norwegian Politics"])
    }

    @MainActor
    func testSearchScopesAndLocallyAppliedFilters() async {
        let service = StubNewsService(home: .failure(.offline))
        await service.setCapabilities(NewsCapabilities(serverSearch: true, serverSearchFilters: [.section]),
                                      search: .success(ArticlePage(items: [summary("a", section: "markets", type: .analysis),
                                                                           summary("b", section: "markets", type: .news)], nextCursor: nil)))
        let model = SearchModel(service: service, index: LoadedArticleIndex(), downloaded: { [] })
        model.filters = SearchFilters(sectionSlug: "markets", editorialType: .analysis)
        await model.search("markets")
        XCTAssertEqual(model.state.value?.scope, .publication)
        XCTAssertEqual(model.state.value?.items.map(\.id.rawValue), ["a"])
        XCTAssertEqual(model.state.value?.locallyAppliedFilters, [.type], "type isn't supported by the server, so it's labelled as local")
        let sent = await service.lastSearchFilters
        XCTAssertEqual(sent?.sectionSlug, "markets")
    }

    @MainActor
    func testUnconfiguredSearchStillSearchesDownloads() async {
        let model = SearchModel(service: UnconfiguredNewsService(reasons: []), index: LoadedArticleIndex(),
                                downloaded: { [summary("d1", headline: "Offline budget story")] })
        await model.search("budget")
        XCTAssertEqual(model.availableScopes, [.downloadedArticles])
        XCTAssertEqual(model.state.value?.items.map(\.id.rawValue), ["d1"])
    }
}

// MARK: - Saved, offline fallback, reading position

final class SavedAndArticleTests: XCTestCase {
    var root: URL!
    override func setUp() { root = tempRoot() }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    struct ServiceFetcher: OfflineFetching {
        let service: NewsService
        func article(id: ArticleID) async throws -> Article { try await service.article(id: id) }
        func imageData(from url: URL) async throws -> Data { throw TransportError.offline }
    }

    @MainActor
    func testDownloadedArticleOpensAfterRestartWhenOfflineAndIsLabelledAsStored() async throws {
        let service = StubNewsService(home: .failure(.offline))
        let article = Article(summary: summary("a", revision: "1"), blocks: [.paragraph(InlineText(plain: "Body"))])
        await service.setArticle(.success(article))
        let offline = OfflineLibrary(root: root.appendingPathComponent("o"))
        let saved = SavedModel(store: BookmarkStore(fileURL: root.appendingPathComponent("b.json")), offline: offline,
                               fetcher: ServiceFetcher(service: service), environment: "test")
        await saved.load()
        await saved.downloadArticle(article.summary)
        XCTAssertTrue(saved.isSaved(ArticleID("a")), "downloading also saves")
        XCTAssertEqual(saved.download(for: ArticleID("a"))?.state, .downloaded)

        // Relaunch, offline.
        await service.setArticle(.failure(.offline))
        let relaunchedSaved = SavedModel(store: BookmarkStore(fileURL: root.appendingPathComponent("b.json")),
                                         offline: OfflineLibrary(root: root.appendingPathComponent("o")),
                                         fetcher: nil, environment: "test")
        await relaunchedSaved.load()
        let model = ArticleModel(id: ArticleID("a"), preview: nil, service: service, saved: relaunchedSaved,
                                 positions: ReadingPositionStore(fileURL: root.appendingPathComponent("p.json")))
        await model.load()
        guard case .loaded(let presentation) = model.state, case .storedCopy(_, let liveError) = presentation.source else {
            return XCTFail("\(model.state)")
        }
        XCTAssertEqual(liveError?.kind, .offline)
        XCTAssertEqual(presentation.article.blocks, article.blocks)

        // Removing the download keeps the bookmark.
        await relaunchedSaved.removeDownload(ArticleID("a"))
        XCTAssertTrue(relaunchedSaved.isSaved(ArticleID("a")))
        XCTAssertNil(relaunchedSaved.download(for: ArticleID("a")))
    }

    @MainActor
    func testUnpublishedArticleIsNotShownFromStaleCopy() async {
        let service = StubNewsService(home: .failure(.offline))
        await service.setArticle(.success(Article(summary: summary("a"), blocks: [.paragraph(InlineText(plain: "x"))])))
        let saved = SavedModel(store: BookmarkStore(fileURL: root.appendingPathComponent("b.json")),
                               offline: OfflineLibrary(root: root.appendingPathComponent("o")),
                               fetcher: ServiceFetcher(service: service), environment: "t")
        await saved.downloadArticle(summary("a"))
        await service.setArticle(.failure(.notFound))
        let model = ArticleModel(id: ArticleID("a"), preview: nil, service: service, saved: saved,
                                 positions: ReadingPositionStore(fileURL: root.appendingPathComponent("p.json")))
        await model.load()
        guard case .failed(let e) = model.state else { return XCTFail() }
        XCTAssertEqual(e.kind, .notFound)
    }

    @MainActor
    func testReadingPositionIsRestored() async {
        let positions = ReadingPositionStore(fileURL: root.appendingPathComponent("p.json"))
        await positions.setPosition(4, for: ArticleID("a"))
        let service = StubNewsService(home: .failure(.offline))
        await service.setArticle(.success(Article(summary: summary("a"), blocks: [])))
        let saved = SavedModel(store: BookmarkStore(fileURL: root.appendingPathComponent("b.json")),
                               offline: OfflineLibrary(root: root.appendingPathComponent("o")), fetcher: nil, environment: "t")
        let model = ArticleModel(id: ArticleID("a"), preview: nil, service: service, saved: saved, positions: positions)
        await model.load()
        XCTAssertEqual(model.resumeBlockIndex, 4)
    }
}

// MARK: - Newsroom model: denied actions, no automatic submission

final class NewsroomModelTests: XCTestCase {
    var root: URL!
    override func setUp() { root = tempRoot() }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    @MainActor
    func testActionsUnavailableWithoutCentralAccessAndNothingIsSent() async throws {
        let transport = FakeTransport()
        let service = NewsroomAPIClient(baseURL: URL(string: "https://news.hakmicapitalgroup.com/api/test-newsroom/v1/")!,
                                        environment: "t", transport: transport, userAgent: "t", token: { "token" })
        let store = DraftStore(root: root)
        let model = NewsroomModel(store: store, service: service, environment: "t", generator: "t") {
            NewsroomAccess(serviceConfigured: true, signedIn: true, centralAccessGranted: false)
        }
        let draft = try await store.create()
        XCTAssertEqual(model.availability(.saveDraft).reason, "HCG has not granted newsroom access to this account in this session.")
        await model.saveToNewsroom(draft.id)
        await model.perform(.publish, draftID: draft.id)
        XCTAssertTrue(transport.requests.isEmpty)
        let after = await store.draft(draft.id)
        XCTAssertNil(after?.serverLink)
    }

    @MainActor
    func testServerDenialIsReportedAndLocalWorkKept() async throws {
        let capabilities = #"{"contractVersion":"1","supportedActions":["save_draft","publish"],"allowedActions":["save_draft","publish"]}"#
        let saved = #"{"id":"srv-1","headline":"H","status":"draft","revision":"1"}"#
        let transport = FakeTransport { request in
            let path = request.url!.path
            if path.hasSuffix("/capabilities") { return (200, Data(capabilities.utf8)) }
            if path.hasSuffix("/drafts") { return (200, Data(saved.utf8)) }
            if path.hasSuffix("/actions/publish") { return (403, Data(#"{"message":"Not authorised to publish."}"#.utf8)) }
            return (404, Data())
        }
        let service = NewsroomAPIClient(baseURL: URL(string: "https://news.hakmicapitalgroup.com/api/test-newsroom/v1/")!,
                                        environment: "t", transport: transport, userAgent: "t", token: { "token" })
        let store = DraftStore(root: root)
        let model = NewsroomModel(store: store, service: service, environment: "t", generator: "t") {
            NewsroomAccess(serviceConfigured: true, signedIn: true, centralAccessGranted: true)
        }
        var draft = try await store.create()
        draft.headline = "H"
        draft = try await store.save(draft)
        await model.loadCapabilities()
        await model.saveToNewsroom(draft.id)
        guard case .succeeded(let message)? = model.lastOutcome else { return XCTFail("\(String(describing: model.lastOutcome))") }
        XCTAssertTrue(message.contains("not been submitted or published"))
        await model.perform(.publish, draftID: draft.id)
        XCTAssertEqual(model.lastOutcome, .failed("Not authorised to publish."))
        let after = await store.draft(draft.id)
        XCTAssertEqual(after?.serverLink?.remoteStatus, "draft", "a refused publish changes nothing locally")
    }

    @MainActor
    func testUnsyncedChangesBlockActionsUntilSaved() async throws {
        let store = DraftStore(root: root)
        let caps = NewsroomCapabilities(contractVersion: "1", supported: [.publish], allowed: [.publish])
        let transport = FakeTransport()
        let model = NewsroomModel(store: store, service: StaticCapsService(caps: caps, transport: transport), environment: "t", generator: "t") {
            NewsroomAccess(serviceConfigured: true, signedIn: true, centralAccessGranted: true)
        }
        await model.loadCapabilities()
        var draft = try await store.create()
        _ = try await store.link(draft.id, to: ServerLink(serverDraftID: "s", serverRevision: "1", remoteStatus: "draft",
                                                         lastSyncedAt: Date(timeIntervalSince1970: 1), environment: "t"))
        draft = try await store.save(await store.draft(draft.id)!)   // local edit after sync
        await model.perform(.publish, draftID: draft.id)
        guard case .failed(let message)? = model.lastOutcome else { return XCTFail() }
        XCTAssertTrue(message.contains("Save to the newsroom first"))
    }

    struct StaticCapsService: NewsroomService {
        let caps: NewsroomCapabilities
        let transport: FakeTransport
        func capabilities() async throws -> NewsroomCapabilities { caps }
        func queue() async throws -> [ServerDraftSummary] { [] }
        func fetchDraft(serverID: String) async throws -> ServerDraftContent { throw NewsroomError.notConfigured }
        func saveDraft(_ draft: Draft, mediaRemoteIDs: [UUID: String]) async throws -> ServerDraftSummary { throw NewsroomError.notConfigured }
        func perform(_ action: NewsroomAction, serverID: String, baseRevision: String, scheduleAt: Date?, note: String?) async throws -> ServerDraftSummary {
            XCTFail("must not be called")
            throw NewsroomError.notConfigured
        }
        func uploadMedia(data: Data, filename: String, mimeType: String) async throws -> String { throw NewsroomError.notConfigured }
        func audit(serverID: String?) async throws -> [AuditEntry] { [] }
    }
}

// MARK: - Diagnostics and logs

final class DiagnosticsTests: XCTestCase {
    func testDiagnosticsContainNoCredentials() async {
        let log = LocalEventLog(fileURL: nil)
        await log.record(.account, "token eyJhbGciOi.eyJzdWIiOiIxIn0.sig and Bearer abc.def")
        let connect = ConnectConfigurationLoader.load(JSONFixture.data(connectJSON()), expectedRedirectScheme: scheme)
        let text = DiagnosticsReport.make(appVersion: "t", publication: (.awaitingSetup, .none), connect: (connect, .bundled),
                                          publicationCheck: "x", connectCheck: "y", offlineCount: 0, offlineBytes: 0,
                                          events: await log.all())
        XCTAssertFalse(text.contains("test-native-client"))
        XCTAssertFalse(text.contains("eyJ"))
        XCTAssertFalse(text.lowercased().contains("bearer abc"))
        XCTAssertTrue(text.contains("not server audit history"))
    }
}
