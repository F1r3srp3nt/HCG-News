import XCTest
import HCGTransport
import HCGTestSupport
@testable import NewsCore

// Fixture-based tests (fictional content, fake fetcher). No live network.

final class FakeOfflineFetcher: OfflineFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var articles: [ArticleID: Result<Article, NewsServiceError>] = [:]
    private var images: [URL: Data] = [:]
    private(set) var articleCalls = 0

    func setArticle(_ id: String, _ result: Result<Article, NewsServiceError>) { lock.withLock { articles[ArticleID(id)] = result } }
    func setImage(_ url: URL, _ data: Data?) { lock.withLock { images[url] = data } }

    func article(id: ArticleID) async throws -> Article {
        let result = lock.withLock { () -> Result<Article, NewsServiceError>? in articleCalls += 1; return articles[id] }
        guard let result else { throw NewsServiceError.notFound }
        return try result.get()
    }

    func imageData(from url: URL) async throws -> Data {
        guard let data = lock.withLock({ images[url] }) else { throw TransportError.offline }
        return data
    }
}

func fixtureArticle(_ id: String, revision: String? = "1", access: AccessLevel = .public, completeness: ContentCompleteness = .full,
                    imageURL: URL? = URL(string: "https://news.hakmicapitalgroup.com/i/\(UUID().uuidString).jpg"),
                    text: String = "Fixture body text.") -> Article {
    let summary = ArticleSummary(id: ArticleID(id), canonicalURL: URL(string: "https://news.hakmicapitalgroup.com/a/\(id)"),
                                 headline: "Fixture \(id)", publishedAt: Date(timeIntervalSince1970: 1_790_000_000),
                                 image: imageURL.map { ArticleImage(url: $0, width: 1200, height: 800, alt: "alt") },
                                 access: access, revision: revision)
    return Article(summary: summary, blocks: completeness == .full ? [.paragraph(InlineText(plain: text))] : [],
                   completeness: completeness)
}

final class OfflineLibraryTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("offline-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testDownloadThenReadAfterRestartWithoutNetwork() async throws {
        let fetcher = FakeOfflineFetcher()
        let article = fixtureArticle("a")
        fetcher.setArticle("a", .success(article))
        fetcher.setImage(article.summary.image!.url, Data([1, 2, 3]))
        let library = OfflineLibrary(root: root)
        let entry = await library.download(ArticleID("a"), headline: "Fixture a", environment: "test", using: fetcher)
        XCTAssertEqual(entry.state, .downloaded)
        XCTAssertEqual(entry.imageCount, 1)
        XCTAssertEqual(entry.missingImages, 0)
        XCTAssertEqual(entry.storedMarker, "r:1")

        // A new instance stands in for a force-quit and relaunch in airplane mode.
        let relaunched = OfflineLibrary(root: root)
        let stored = await relaunched.storedArticle(ArticleID("a"))
        XCTAssertEqual(stored?.article, article)
        let image = await relaunched.localImage(for: article.summary.image!.url, article: ArticleID("a"))
        XCTAssertNotNil(image)
        XCTAssertEqual(try Data(contentsOf: image!), Data([1, 2, 3]))
    }

    func testFailedUpdateKeepsPreviousCopy() async throws {
        let fetcher = FakeOfflineFetcher()
        fetcher.setArticle("a", .success(fixtureArticle("a", imageURL: nil)))
        let library = OfflineLibrary(root: root)
        await library.download(ArticleID("a"), headline: "a", environment: "test", using: fetcher)
        fetcher.setArticle("a", .failure(.offline))
        let entry = await library.download(ArticleID("a"), headline: "a", environment: "test", using: fetcher)
        XCTAssertEqual(entry.state, .failed(reason: "You're offline."))
        XCTAssertTrue(entry.hasCompleteCopy)
        let stored = await library.storedArticle(ArticleID("a"))
        XCTAssertNotNil(stored, "a failed update must not destroy the previous good copy")
    }

    func testMissingImageStillDownloadsTextAndCountsIt() async {
        let fetcher = FakeOfflineFetcher()
        fetcher.setArticle("a", .success(fixtureArticle("a")))   // image not provided
        let entry = await OfflineLibrary(root: root).download(ArticleID("a"), headline: "a", environment: "t", using: fetcher)
        XCTAssertEqual(entry.state, .downloaded)
        XCTAssertEqual(entry.missingImages, 1)
    }

    func testRestrictedAndSummaryOnlyAreRefused() async {
        let fetcher = FakeOfflineFetcher()
        fetcher.setArticle("r", .success(fixtureArticle("r", access: .restricted, imageURL: nil)))
        fetcher.setArticle("s", .success(fixtureArticle("s", completeness: .summaryOnly, imageURL: nil)))
        let library = OfflineLibrary(root: root)
        let r = await library.download(ArticleID("r"), headline: "r", environment: "t", using: fetcher)
        let s = await library.download(ArticleID("s"), headline: "s", environment: "t", using: fetcher)
        XCTAssertEqual(r.state, .failed(reason: "Restricted articles aren't stored for offline reading."))
        XCTAssertFalse(r.hasCompleteCopy)
        XCTAssertEqual(s.state, .failed(reason: "Only a summary is available, so there is nothing to download."))
        let storedR = await library.storedArticle(ArticleID("r"))
        XCTAssertNil(storedR)
    }

    func testInterruptedDownloadIsRecoverable() async throws {
        // Simulate a crash: a manifest left in the downloading state.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = """
        {"version":1,"entries":[{"articleID":"a","headline":"a","state":{"downloading":{}},"bytes":0,"imageCount":0,"missingImages":0,"environment":"t"}]}
        """
        try Data(manifest.utf8).write(to: root.appendingPathComponent("manifest.json"))
        let library = OfflineLibrary(root: root)
        let recovered = await library.recoverInterrupted()
        XCTAssertEqual(recovered, [ArticleID("a")])
        let entry = await library.entry(for: ArticleID("a"))
        XCTAssertEqual(entry?.state, .interrupted)
        let fetcher = FakeOfflineFetcher()
        fetcher.setArticle("a", .success(fixtureArticle("a", imageURL: nil)))
        let resumed = await library.download(ArticleID("a"), headline: "a", environment: "t", using: fetcher)
        XCTAssertEqual(resumed.state, .downloaded)
    }

    func testUpdateAvailableOnlyWhenPublicationReportsNewerVersion() async {
        let fetcher = FakeOfflineFetcher()
        fetcher.setArticle("a", .success(fixtureArticle("a", revision: "1", imageURL: nil)))
        let library = OfflineLibrary(root: root)
        await library.download(ArticleID("a"), headline: "a", environment: "t", using: fetcher)
        await library.noteLatest(marker: "r:1", for: ArticleID("a"))
        let same = await library.entry(for: ArticleID("a"))
        XCTAssertFalse(same!.updateAvailable)
        await library.noteLatest(marker: "r:2", for: ArticleID("a"))
        let newer = await library.entry(for: ArticleID("a"))
        XCTAssertTrue(newer!.updateAvailable)
    }

    func testStorageLimitRefusesWithoutDeletingOtherDownloads() async {
        let fetcher = FakeOfflineFetcher()
        fetcher.setArticle("a", .success(fixtureArticle("a", imageURL: nil, text: String(repeating: "x", count: 2000))))
        fetcher.setArticle("b", .success(fixtureArticle("b", imageURL: nil, text: String(repeating: "y", count: 2000))))
        let library = OfflineLibrary(root: root)
        let a = await library.download(ArticleID("a"), headline: "a", environment: "t", using: fetcher, limitBytes: 4000)
        XCTAssertEqual(a.state, .downloaded)
        let b = await library.download(ArticleID("b"), headline: "b", environment: "t", using: fetcher, limitBytes: 4000)
        guard case .failed(let reason) = b.state else { return XCTFail("\(b.state)") }
        XCTAssertTrue(reason.contains("limit"))
        let storedA = await library.storedArticle(ArticleID("a"))
        XCTAssertNotNil(storedA)
    }

    func testRemoveAndClear() async {
        let fetcher = FakeOfflineFetcher()
        fetcher.setArticle("a", .success(fixtureArticle("a", imageURL: nil)))
        fetcher.setArticle("b", .success(fixtureArticle("b", imageURL: nil)))
        let library = OfflineLibrary(root: root)
        await library.download(ArticleID("a"), headline: "a", environment: "t", using: fetcher)
        await library.download(ArticleID("b"), headline: "b", environment: "t", using: fetcher)
        await library.remove(ArticleID("a"))
        let remaining = await library.entries().map(\.articleID)
        XCTAssertEqual(remaining, [ArticleID("b")])
        await library.removeAll()
        let usage = await library.usageBytes()
        XCTAssertEqual(usage, 0)
    }
}

final class BookmarkMigrationTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testVersion1FileIsMigratedAndBackedUp() async throws {
        let url = dir.appendingPathComponent("bookmarks.json")
        let v1 = """
        {"version":1,"bookmarks":[
          {"articleID":"a","headline":"Old A","editorialType":"HCG Announcement","savedAt":"2026-11-01T10:00:00Z","canonicalURL":"https://news.hakmicapitalgroup.com/a"},
          {"articleID":"b","headline":"Old B","editorialType":"Analysis","savedAt":"2026-11-02T10:00:00Z"}
        ]}
        """
        try Data(v1.utf8).write(to: url)
        let store = BookmarkStore(fileURL: url)
        let all = await store.all()
        XCTAssertEqual(all.map(\.articleID.rawValue), ["b", "a"])
        XCTAssertEqual(all[1].editorialTypeWire, "announcement")
        XCTAssertEqual(all[1].editorialTypeLabel, "HCG Announcement")
        XCTAssertEqual(all[0].editorialType, .analysis)
        let migrated = await store.migratedFromVersion
        XCTAssertEqual(migrated, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bookmarks.v1-backup.json").path))
        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(written.contains("\"version\":2"))

        // Relaunch reads v2 without migrating again.
        let again = BookmarkStore(fileURL: url)
        let reread = await again.all()
        XCTAssertEqual(reread.count, 2)
        let migratedAgain = await again.migratedFromVersion
        XCTAssertNil(migratedAgain)
    }

    func testNewerFileVersionIsNeverOverwritten() async throws {
        let url = dir.appendingPathComponent("bookmarks.json")
        let future = #"{"version":9,"bookmarks":[{"articleID":"x","headline":"Future","savedAt":"2026-11-01T10:00:00Z"}],"newField":true}"#
        try Data(future.utf8).write(to: url)
        let store = BookmarkStore(fileURL: url)
        do {
            try await store.save(ArticleSummary(id: ArticleID("y"), headline: "New", publishedAt: Date()))
            XCTFail("writes must be refused")
        } catch {
            XCTAssertEqual(error as? BookmarkStoreError, .newerFileVersion(9))
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), future)
    }

    func testReadingPositionsPersist() async {
        let url = dir.appendingPathComponent("pos.json")
        let store = ReadingPositionStore(fileURL: url, limit: 2)
        await store.setPosition(5, for: ArticleID("a"), at: Date(timeIntervalSince1970: 1))
        await store.setPosition(7, for: ArticleID("b"), at: Date(timeIntervalSince1970: 2))
        await store.setPosition(9, for: ArticleID("c"), at: Date(timeIntervalSince1970: 3))
        let relaunched = ReadingPositionStore(fileURL: url, limit: 2)
        let a = await relaunched.position(for: ArticleID("a"))
        let c = await relaunched.position(for: ArticleID("c"))
        XCTAssertNil(a, "oldest entry trimmed")
        XCTAssertEqual(c?.blockIndex, 9)
    }
}

final class StorageCodingAndWireTests: XCTestCase {
    func testArticleRoundTripsThroughStorageEncoding() throws {
        let article = Article(
            summary: ArticleSummary(id: ArticleID("a"), headline: "H", publishedAt: Date(timeIntervalSince1970: 1_790_000_000), revision: "7"),
            blocks: [.heading(level: 2, text: InlineText(plain: "Sub")), .paragraph(InlineText([InlineRun("b", bold: true)])),
                     .list(ordered: true, items: [ListItem(text: InlineText(plain: "1"))]),
                     .quote(paragraphs: [InlineText(plain: "q")], attribution: "x"), .divider, .embedNotice(host: "v.example"),
                     .unsupported(type: "poll")],
            corrections: [ArticleCorrection(id: "c1", text: "Fixed a date.", issuedAt: Date(timeIntervalSince1970: 1_790_000_100))],
            sponsor: SponsorNotice(sponsorName: "Fixture Sponsor", text: nil, url: nil),
            audio: ArticleAudio(url: URL(string: "https://news.hakmicapitalgroup.com/a.m4a")!, durationSeconds: 61))
        let data = try HCGJSON.makeEncoder().encode(article)
        XCTAssertEqual(try HCGJSON.makeDecoder().decode(Article.self, from: data), article)
    }

    func testOptionalEditorialMetadataIsDecodedButNeverInvented() throws {
        var object = JSONFixture.summary(id: "a1")
        object["revision"] = 42
        object["body"] = ["format": "html", "html": "<p>Body</p>"]
        object["corrections"] = [["id": "c1", "text": "Corrected the conference date.", "issuedAt": "2026-11-05T10:00:00Z"],
                                 ["id": "c2", "text": "   "]]
        object["sponsor"] = ["sponsorName": "Fixture Partner"]
        object["audio"] = ["url": "http://insecure.example/a.mp3"]
        object["related"] = [JSONFixture.summary(id: "r1"), JSONFixture.summary(id: "r-draft", status: "draft"), JSONFixture.summary(id: "a1")]
        let response = try HCGJSON.makeDecoder().decode(ArticleResponse.self, from: JSONFixture.data(object))
        let article = response.article(baseURL: nil, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(article.summary.revision, "42")
        XCTAssertEqual(article.corrections.map(\.id), ["c1"], "blank corrections are dropped")
        XCTAssertEqual(article.sponsor?.sponsorName, "Fixture Partner")
        XCTAssertNil(article.audio, "non-HTTPS audio is refused")
        XCTAssertEqual(article.related.map(\.id.rawValue), ["r1"], "drafts and self-references are not related stories")
        XCTAssertEqual(article.completeness, .full)

        var none = JSONFixture.summary(id: "a2")
        none["body"] = ["format": "summary"]
        let summaryOnly = try HCGJSON.makeDecoder().decode(ArticleResponse.self, from: JSONFixture.data(none)).article(baseURL: nil)
        XCTAssertEqual(summaryOnly.completeness, .summaryOnly)
        XCTAssertTrue(summaryOnly.corrections.isEmpty)
        XCTAssertNil(summaryOnly.sponsor)
        XCTAssertTrue(summaryOnly.related.isEmpty)
        XCTAssertFalse(summaryOnly.isEligibleForOfflineStorage)
    }

    func testUnknownBodyFormatKeepsArticleWithNotice() throws {
        var object = JSONFixture.summary(id: "a1")
        object["body"] = ["format": "prosemirror"]
        let article = try HCGJSON.makeDecoder().decode(ArticleResponse.self, from: JSONFixture.data(object)).article(baseURL: nil)
        XCTAssertEqual(article.blocks, [.unsupported(type: "prosemirror")])
        XCTAssertEqual(article.summary.headline, "Test fixture headline")
    }

    func testSearchFiltersMatchLocally() {
        let a = ArticleSummary(id: ArticleID("1"), headline: "x", section: SectionRef(id: "s", slug: "markets", name: "Markets"),
                               editorialType: .analysis, publishedAt: Date())
        XCTAssertTrue(SearchFilters(sectionSlug: "markets").matches(a))
        XCTAssertFalse(SearchFilters(editorialType: .opinion).matches(a))
        XCTAssertTrue(SearchFilters(editorialType: .opinion).matches(a, kinds: [.section]), "only the given kinds are applied")
    }
}
