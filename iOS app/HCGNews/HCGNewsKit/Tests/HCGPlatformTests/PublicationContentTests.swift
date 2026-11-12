import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import HCGTestSupport
import NewsCore
@testable import HCGPlatform

final class PlatformConfigurationTests: XCTestCase {
    func file(_ platform: [String: Any]) -> Data { json(["hcgPlatform": platform]) }
    let valid: [String: Any] = [
        "environment": "production", "projectURL": "https://qggdyzoydveafkmjgkpq.supabase.co",
        "publicClientKey": testAnonKey, "websiteURL": "https://beta.hakmicapitalgroup.com",
        "publicationURL": "https://news.hakmicapitalgroup.com", "approvedByFounder": true,
    ]

    func testValidPlatformConfigurationIsReady() {
        guard case .ready(let c) = NewsConfigurationLoader.load(file(valid)) else { return XCTFail("expected ready") }
        XCTAssertEqual(c.platform?.projectRef, "qggdyzoydveafkmjgkpq")
        XCTAssertEqual(c.publicationURL.host, "news.hakmicapitalgroup.com")
        XCTAssertEqual(c.environment, "production")
    }

    func testPrivilegedKeysOtherProjectsAndUnapprovedFilesAreRefused() {
        // A service-role JWT for the same project (payload role=service_role).
        let servicePayload = Data(#"{"iss":"supabase","ref":"qggdyzoydveafkmjgkpq","role":"service_role"}"#.utf8)
            .base64EncodedString().replacingOccurrences(of: "=", with: "")
        let cases: [[String: Any]] = [
            valid.merging(["publicClientKey": "x.\(servicePayload).y"]) { $1 },
            valid.merging(["publicClientKey": "sb_secret_abc"]) { $1 },
            valid.merging(["projectURL": "https://otherproject12345678.supabase.co"]) { $1 },
            valid.merging(["projectURL": "http://qggdyzoydveafkmjgkpq.supabase.co"]) { $1 },
            valid.merging(["websiteURL": "https://example.com"]) { $1 },
            valid.merging(["approvedByFounder": false]) { $1 },
        ]
        for c in cases {
            guard case .invalid(let problems) = NewsConfigurationLoader.load(file(c)) else { return XCTFail("accepted \(c)") }
            XCTAssertFalse(problems.isEmpty)
        }
        // A field named like a secret anywhere is refused outright.
        guard case .invalid = NewsConfigurationLoader.load(file(valid.merging(["service_role_key": "x"]) { $1 })) else { return XCTFail() }
    }
}

final class PublicationContentTests: XCTestCase {
    func service(_ transport: FakeTransport) -> PublicationContentService {
        PublicationContentService(client: PlatformClient(configuration: testPlatform, transport: transport, userAgent: "test"),
                                  now: { fixedNow })
    }

    func testPublicListsAreAnonymousPublishedOnlyAndNeverAskForEditorialColumns() async throws {
        let transport = FakeTransport { _ in (200, json([articleRow(id: "11111111-1111-1111-1111-111111111111")])) }
        let page = try await service(transport).articles(sectionSlug: nil, cursor: nil)
        XCTAssertEqual(page.items.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.path, "/rest/v1/news_articles")
        XCTAssertEqual(request.bearer, testAnonKey, "public reading never sends a person's token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), testAnonKey)
        XCTAssertEqual(request.query["status"], "eq.published")
        XCTAssertEqual(request.query["published_at"], "lte.\(HCGJSON.formatDate(fixedNow))")
        let select = try XCTUnwrap(request.query["select"])
        for forbidden in ["created_by", "seo_", "view_count", "body", "*", "tags"] {
            XCTAssertFalse(select.contains(forbidden), "public list must not request \(forbidden)")
        }
        XCTAssertTrue(request.url!.absoluteString.contains("lte.2026"), "timestamp sent")
        XCTAssertFalse(request.url!.absoluteString.contains("+00:00"), "plus signs are percent-encoded")
    }

    func testMappingLabelsDisclosureCanonicalURLAndDemo() async throws {
        let id = "22222222-2222-2222-2222-222222222222"
        let transport = FakeTransport { _ in (200, json([articleRow(id: id, breaking: true, demo: true)])) }
        let page = try await service(transport).articles(sectionSlug: nil, cursor: nil)
        let item = try XCTUnwrap(page.items.first)
        XCTAssertEqual(item.editorialType, .analysis)
        XCTAssertEqual(item.section?.slug, "markets")
        XCTAssertEqual(item.canonicalURL?.absoluteString, "https://news.hakmicapitalgroup.com/markets/fixture-22222222")
        XCTAssertTrue(item.isDemo)
        XCTAssertFalse(BreakingNewsRule.isBreaking(item), "demo content is never breaking news")
        XCTAssertEqual(item.disclosures.first?.text, "Author disclosure: Yasin Ludvigsen Hakmi is a politician affiliated with FrP and FpU.")
        XCTAssertEqual(item.revision, "2026-11-10T09:00:00.123456+00:00")
        XCTAssertNotNil(item.updatedAt, "microsecond timestamps parse")
    }

    func testArticlesWithoutSectionUseTheNewsPath() {
        let url = PublicationMapping.canonicalURL(publicationURL: testPlatform.publicationURL, sectionSlug: nil, slug: "a-b")
        XCTAssertEqual(url?.absoluteString, "https://news.hakmicapitalgroup.com/news/a-b")
    }

    func testDraftsAndScheduledRowsAreDroppedEvenIfTheServerSendsThem() async throws {
        let rows = [articleRow(id: "a", status: "draft"),
                    articleRow(id: "b", publishedAt: fixedNow.addingTimeInterval(86_400)),
                    articleRow(id: "c")]
        let data = json(rows)
        let transport = FakeTransport { _ in (200, data) }
        let page = try await service(transport).articles(sectionSlug: nil, cursor: nil)
        XCTAssertEqual(page.items.map(\.id.rawValue), ["c"])
    }

    func testArticleDetailRefusesUnpublishedAndParsesBodySourcesAndCorrections() async throws {
        let id = "33333333-3333-3333-3333-333333333333"
        let transport = FakeTransport { _ in
            (200, json([articleRow(id: id, extra: ["body": "<p>Hello <strong>world</strong></p><script>x()</script>",
                                                  "sources": "Statistics Norway https://www.ssb.no/x\nInterview",
                                                  "correction_notes": "An earlier version misstated a figure."])]))
        }
        let article = try await service(transport).article(id: ArticleID(id))
        XCTAssertEqual(article.blocks.first, .paragraph(InlineText([InlineRun("Hello "), InlineRun("world", bold: true)])))
        XCTAssertEqual(article.sources.map(\.url?.host), ["www.ssb.no", nil])
        XCTAssertEqual(article.corrections.first?.text, "An earlier version misstated a figure.")
        let select = try XCTUnwrap(transport.requests.first?.query["select"])
        XCTAssertTrue(select.contains("body"))
        XCTAssertFalse(select.contains("created_by"))

        transport.setHandler { _ in (200, json([articleRow(id: id, status: "in_review", extra: ["body": "<p>x</p>"])])) }
        do { _ = try await service(transport).article(id: ArticleID(id)); XCTFail("draft shown") }
        catch let e as NewsServiceError { XCTAssertEqual(e, .notFound) }

        do { _ = try await service(transport).article(id: ArticleID("not-a-uuid")); XCTFail() }
        catch let e as NewsServiceError { XCTAssertEqual(e, .notFound) }
    }

    func testPaginationUsesOneExtraRowAndOffsetCursor() async throws {
        let rows = (0..<21).map { articleRow(id: "id-\($0)", publishedAt: fixedNow.addingTimeInterval(Double(-$0 - 1) * 60)) }
        let data = json(rows)
        let transport = FakeTransport { _ in (200, data) }
        let first = try await service(transport).articles(sectionSlug: nil, cursor: nil)
        XCTAssertEqual(first.items.count, 20)
        XCTAssertEqual(first.nextCursor, "offset:20")
        XCTAssertEqual(transport.requests.last?.query["limit"], "21")
        transport.setHandler { _ in (200, json([articleRow(id: "last")])) }
        let second = try await service(transport).articles(sectionSlug: nil, cursor: first.nextCursor)
        XCTAssertNil(second.nextCursor)
        XCTAssertEqual(transport.requests.last?.query["offset"], "20")
    }

    func testSectionFeedResolvesSlugAndSearchEscapesInput() async throws {
        let transport = FakeTransport { request in
            if request.path.hasSuffix("news_categories") {
                return (200, json([["id": "c1", "name": "Markets", "slug": "markets", "description": NSNull(), "sort_order": 1]]))
            }
            return (200, json([]))
        }
        let svc = service(transport)
        _ = try await svc.articles(sectionSlug: "markets", cursor: nil)
        XCTAssertEqual(transport.requests.last?.query["category_id"], "eq.c1")
        XCTAssertEqual(transport.requests.first?.query["is_visible"], "eq.true")

        _ = try await svc.search(query: "oil, (price)* \"x\"", filters: SearchFilters(sectionSlug: "markets", editorialType: .opinion), cursor: nil)
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.query["or"], "(title.ilike.\"*oil, (price) x*\",subtitle.ilike.\"*oil, (price) x*\",excerpt.ilike.\"*oil, (price) x*\")")
        XCTAssertEqual(request.query["content_type"], "eq.opinion")
        XCTAssertEqual(request.query["status"], "eq.published")

        let unknown = try await svc.articles(sectionSlug: "does-not-exist", cursor: nil)
        XCTAssertTrue(unknown.items.isEmpty)
    }

    func testFailuresMapToHonestStates() async {
        let cases: [(Int, NewsServiceError)] = [(503, .unavailable), (429, .rateLimited), (500, .server(status: 500))]
        for (status, expected) in cases {
            let transport = FakeTransport { _ in (status, Data()) }
            do { _ = try await service(transport).home(); XCTFail() }
            catch let e as NewsServiceError { XCTAssertEqual(e, expected) }
            catch { XCTFail("\(error)") }
        }
        let offline = FakeTransport { _ in throw TransportError.offline }
        do { _ = try await service(offline).sections(); XCTFail() }
        catch let e as NewsServiceError { XCTAssertEqual(e, .offline) }
        catch { XCTFail() }
    }

    func testConnectionCheckReportsWhenNoArticleIsReadable() async throws {
        let empty = FakeTransport { _ in (200, json([])) }
        do { _ = try await service(empty).verifyConnection(); XCTFail("empty publication reported as connected") }
        catch let e as NewsServiceError { XCTAssertEqual(e, .noPublicContent) }
        let ok = FakeTransport { _ in (200, json([["id": "x"]])) }
        _ = try await service(ok).verifyConnection()
    }

    func testHomeAsksForFeaturedAndNonDemoBreaking() async throws {
        let transport = FakeTransport { _ in (200, json([])) }
        _ = try await service(transport).home()
        let queries = transport.requests.map(\.query)
        XCTAssertTrue(queries.contains { $0["is_featured"] == "eq.true" })
        XCTAssertTrue(queries.contains { $0["is_breaking"] == "eq.true" && $0["is_demo"] == "is.false" })
        XCTAssertTrue(queries.allSatisfy { $0["status"] == "eq.published" })
    }
}
