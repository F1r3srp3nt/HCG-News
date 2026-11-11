import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import HCGTestSupport
@testable import NewsCore

final class NewsAPIClientTests: XCTestCase {
    static let base = "https://news.hakmicapitalgroup.com/api/public/news/v1/"
    let configuration = NewsContentConfiguration(
        contractVersion: "1", environment: "test", apiBaseURL: URL(string: base)!,
        publicationURL: URL(string: "https://news.hakmicapitalgroup.com")!, approvedByFounder: true)
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func client(_ transport: FakeTransport, token: String? = nil) -> NewsAPIClient {
        let fixedNow = now
        return NewsAPIClient(configuration: configuration, transport: transport, userAgent: "HCGNews-Tests",
                             accessToken: { token }, now: { fixedNow })
    }

    func transport(_ routes: [String: @Sendable (URLRequest) -> (Int, Data)]) -> FakeTransport {
        let router = Router(routes)
        let base = Self.base
        return FakeTransport { request in router.handle(request, base: base) }
    }

    static func ok(_ object: Any) -> @Sendable (URLRequest) -> (Int, Data) {
        let data = JSONFixture.data(object)
        return { _ in (200, data) }
    }

    func testHomeFiltersUnpublishedAndUsesExplicitFlags() async throws {
        let published = now.addingTimeInterval(-600)
        let t = transport([
            "meta": Self.ok(JSONFixture.meta()),
            "home": Self.ok([
                "featured": [
                    JSONFixture.summary(id: "f1", publishedAt: published, featured: true),
                    JSONFixture.summary(id: "f-not-flagged", publishedAt: published, featured: false),
                    JSONFixture.summary(id: "f-draft", publishedAt: published, status: "draft", featured: true),
                ],
                "breaking": [JSONFixture.summary(id: "b1", publishedAt: published, breaking: ["active": true])],
                "latest": ["items": [
                    JSONFixture.summary(id: "l1", publishedAt: published),
                    JSONFixture.summary(id: "l-private", publishedAt: published, status: "private"),
                    JSONFixture.summary(id: "l-future", publishedAt: now.addingTimeInterval(86_400)),
                    JSONFixture.summary(id: "l-breaking", publishedAt: published.addingTimeInterval(60), breaking: ["active": true]),
                ], "nextCursor": "c2"],
            ]),
        ])
        let home = try await client(t).home()
        XCTAssertEqual(home.featured.map(\.id.rawValue), ["f1"])
        XCTAssertEqual(home.latest.items.map(\.id.rawValue), ["l1", "l-breaking"])
        XCTAssertEqual(home.breaking.map(\.id.rawValue), ["l-breaking", "b1"])
        XCTAssertEqual(home.latest.nextCursor, "c2")
        XCTAssertTrue(t.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil },
                      "public content is requested anonymously")
    }

    func testContractVersionMismatchStopsEverything() async {
        let t = transport(["meta": Self.ok(JSONFixture.meta(version: "9"))])
        do {
            _ = try await client(t).home()
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? NewsServiceError, .unsupportedContractVersion("9"))
            XCTAssertEqual(t.requests.count, 1, "nothing else is requested after a version mismatch")
        }
    }

    func testArticleDetailAndPathEncoding() async throws {
        var detail = JSONFixture.summary(id: "id/with space", publishedAt: now.addingTimeInterval(-60))
        detail["body"] = ["format": "html", "html": "<p>Body</p>"]
        let t = transport([
            "meta": Self.ok(JSONFixture.meta()),
            "articles/id%2Fwith%20space": Self.ok(detail),
        ])
        let article = try await client(t).article(id: ArticleID("id/with space"))
        XCTAssertEqual(article.blocks, [.paragraph(InlineText(plain: "Body"))])
    }

    func testDraftDetailIsTreatedAsNotFound() async {
        var detail = JSONFixture.summary(id: "d1", status: "draft")
        detail["body"] = ["format": "html", "html": "<p>Unpublished draft text</p>"]
        let t = transport(["meta": Self.ok(JSONFixture.meta()), "articles/d1": Self.ok(detail)])
        do {
            _ = try await client(t).article(id: ArticleID("d1"))
            XCTFail("draft must not be returned")
        } catch {
            XCTAssertEqual(error as? NewsServiceError, .notFound)
        }
    }

    func testRestrictedArticleWithoutSignInReportsRestricted() async {
        let t = transport(["meta": Self.ok(JSONFixture.meta()), "articles/r1": { _ in (401, Data()) }])
        do {
            _ = try await client(t, token: nil).article(id: ArticleID("r1"))
            XCTFail()
        } catch {
            XCTAssertEqual(error as? NewsServiceError, .restricted)
        }
    }

    func testRestrictedArticleRetriesOnceWithBearerWhenSignedIn() async throws {
        var detail = JSONFixture.summary(id: "r1", access: "restricted")
        detail["body"] = ["format": "html", "html": "<p>Members text</p>"]
        let detailData = JSONFixture.data(detail)
        let t = transport([
            "meta": Self.ok(JSONFixture.meta()),
            "articles/r1": { request in
                request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token" ? (200, detailData) : (401, Data())
            },
        ])
        let article = try await client(t, token: "test-token").article(id: ArticleID("r1"))
        XCTAssertEqual(article.summary.access, .restricted)
        let articleRequests = t.requests.filter { $0.url!.path.hasSuffix("articles/r1") }
        XCTAssertEqual(articleRequests.count, 2)
        XCTAssertNil(articleRequests[0].value(forHTTPHeaderField: "Authorization"))
    }

    func testErrorMapping() async {
        let cases: [(Int, NewsServiceError)] = [(404, .notFound), (410, .notFound), (429, .rateLimited), (503, .unavailable), (500, .server(status: 500))]
        for (status, expected) in cases {
            let t = transport(["meta": Self.ok(JSONFixture.meta()), "sections": { _ in (status, Data()) }])
            do {
                _ = try await client(t).sections()
                XCTFail()
            } catch {
                XCTAssertEqual(error as? NewsServiceError, expected, "status \(status)")
            }
        }
    }

    func testOfflineIsReportedAsOffline() async {
        let t = FakeTransport { _ in throw TransportError.offline }
        do {
            _ = try await client(t).home()
            XCTFail()
        } catch {
            XCTAssertEqual(error as? NewsServiceError, .offline)
        }
    }

    func testMalformedResponseIsContractMismatchWithoutEchoingContent() async {
        let t = transport(["meta": Self.ok(JSONFixture.meta()), "sections": Self.ok(["sections": [["id": "x"]]])])
        do {
            _ = try await client(t).sections()
            XCTFail()
        } catch NewsServiceError.contractMismatch(let message) {
            XCTAssertTrue(message.contains("slug") || message.contains("name"), message)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testSectionsSortedByPositionThenName() async throws {
        let t = transport([
            "meta": Self.ok(JSONFixture.meta()),
            "sections": Self.ok(["sections": [
                ["id": "3", "slug": "business", "name": "Business"],
                ["id": "1", "slug": "politics", "name": "Politics", "position": 1],
                ["id": "2", "slug": "norwegian-politics", "name": "Norwegian Politics", "parentSlug": "politics", "position": 2],
            ]]),
        ])
        let sections = try await client(t).sections()
        XCTAssertEqual(sections.map(\.slug), ["politics", "norwegian-politics", "business"])
    }

    func testSearchOnlyWhenServerSupportsIt() async throws {
        let unsupported = transport(["meta": Self.ok(JSONFixture.meta(search: false))])
        let caps = try await client(unsupported).capabilities()
        XCTAssertFalse(caps.serverSearch)

        let supported = transport([
            "meta": Self.ok(JSONFixture.meta(search: true)),
            "search": Self.ok(["items": [JSONFixture.summary(id: "s1")], "nextCursor": NSNull()]),
        ])
        let page = try await client(supported).search(query: "test query", cursor: nil)
        XCTAssertEqual(page.items.count, 1)
        let searchURL = supported.requests.last!.url!
        XCTAssertTrue(searchURL.absoluteString.contains("q=test%20query"))
    }

    func testUnconfiguredServiceNeverReturnsContent() async {
        let service = UnconfiguredNewsService(reasons: [])
        do {
            _ = try await service.home()
            XCTFail()
        } catch {
            XCTAssertEqual(error as? NewsServiceError, .notConfigured)
        }
    }
}
