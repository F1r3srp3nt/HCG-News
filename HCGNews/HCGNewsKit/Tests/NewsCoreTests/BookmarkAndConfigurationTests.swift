import XCTest
import HCGTransport
import HCGTestSupport
@testable import NewsCore

final class BookmarkStoreTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hcgnews-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func article(_ id: String, headline: String = "Fictional headline") -> ArticleSummary {
        ArticleSummary(id: ArticleID(id), canonicalURL: URL(string: "https://news.hakmicapitalgroup.com/a/\(id)"),
                       headline: headline, publishedAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    func testBookmarksPersistAcrossRelaunch() async throws {
        let url = directory.appendingPathComponent("bookmarks.json")
        let first = BookmarkStore(fileURL: url)
        try await first.save(article("a"), at: Date(timeIntervalSince1970: 1))
        try await first.save(article("b"), at: Date(timeIntervalSince1970: 2))

        // A new store instance reading the same file stands in for an app relaunch.
        let relaunched = BookmarkStore(fileURL: url)
        let all = await relaunched.all()
        XCTAssertEqual(all.map(\.articleID.rawValue), ["b", "a"], "most recently saved first")
        let containsA = await relaunched.contains(ArticleID("a"))
        XCTAssertTrue(containsA)
    }

    func testToggleAndRemove() async throws {
        let store = BookmarkStore(fileURL: directory.appendingPathComponent("b.json"))
        let saved = try await store.toggle(article("a"))
        XCTAssertTrue(saved)
        let unsaved = try await store.toggle(article("a"))
        XCTAssertFalse(unsaved)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testResavingRefreshesSnapshotButKeepsSaveTimeAndID() async throws {
        let store = BookmarkStore(fileURL: directory.appendingPathComponent("b.json"))
        try await store.save(article("a", headline: "Old"), at: Date(timeIntervalSince1970: 10))
        try await store.save(article("a", headline: "Updated headline"), at: Date(timeIntervalSince1970: 99))
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].headline, "Updated headline")
        XCTAssertEqual(all[0].savedAt, Date(timeIntervalSince1970: 10))
    }

    func testStoredFileHoldsNoArticleBody() async throws {
        let url = directory.appendingPathComponent("b.json")
        let store = BookmarkStore(fileURL: url)
        try await store.save(article("a"))
        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(json.contains("blocks"))
        XCTAssertFalse(json.contains("body"))
        XCTAssertTrue(json.contains("\"articleID\":\"a\""))
    }

    func testCorruptFileIsPreservedNotOverwritten() async throws {
        let url = directory.appendingPathComponent("bookmarks.json")
        try Data("not json".utf8).write(to: url)
        let store = BookmarkStore(fileURL: url)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
        let recovered = await store.recoveredFromCorruption
        XCTAssertTrue(recovered)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains("corrupt") }
        XCTAssertEqual(backups.count, 1)
    }
}

final class NewsConfigurationTests: XCTestCase {
    func config(_ content: [String: Any]) -> NewsConfigurationState {
        NewsConfigurationLoader.load(JSONFixture.data(["content": content]))
    }

    let valid: [String: Any] = [
        "contractVersion": "1", "environment": "beta", "approvedByFounder": true,
        "apiBaseURL": "https://news.hakmicapitalgroup.com/api/public/news/v1",
        "publicationURL": "https://news.hakmicapitalgroup.com",
    ]

    func testNoFileMeansAwaitingSetup() {
        XCTAssertEqual(NewsConfigurationLoader.load(nil), .awaitingSetup)
        XCTAssertEqual(NewsConfigurationLoader.load(JSONFixture.data([:])), .awaitingSetup)
    }

    func testValidConfigurationIsReadyAndBaseGetsTrailingSlash() {
        guard case .ready(let c) = config(valid) else { return XCTFail("expected ready") }
        XCTAssertEqual(c.apiBaseURL.absoluteString, "https://news.hakmicapitalgroup.com/api/public/news/v1/")
    }

    func testPlaceholdersAndUnapprovedAreInvalid() {
        var placeholder = valid
        placeholder["apiBaseURL"] = "https://<central>/<news-api>"
        guard case .invalid = config(placeholder) else { return XCTFail() }
        var unapproved = valid
        unapproved["approvedByFounder"] = false
        guard case .invalid(let problems) = config(unapproved) else { return XCTFail() }
        XCTAssertTrue(problems.contains { $0.contains("approved") })
    }

    func testNonHCGOrInsecureHostsAreRejected() {
        for bad in ["http://news.hakmicapitalgroup.com/api", "https://news.example.com/api", "https://hakmicapitalgroup.com.evil.example/api"] {
            var c = valid
            c["apiBaseURL"] = bad
            guard case .invalid = config(c) else { return XCTFail("\(bad) should be rejected") }
        }
    }

    func testSecretsAreRejected() {
        var c = valid
        c["clientSecret"] = "x"
        guard case .invalid(let problems) = config(c) else { return XCTFail() }
        XCTAssertTrue(problems[0].contains("content.clientSecret"))
    }

    func testUnsupportedContractVersion() {
        var c = valid
        c["contractVersion"] = "2"
        guard case .invalid = config(c) else { return XCTFail() }
    }
}
