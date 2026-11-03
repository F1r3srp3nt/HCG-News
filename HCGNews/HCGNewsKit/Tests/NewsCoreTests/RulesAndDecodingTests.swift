import XCTest
import HCGTransport
import HCGTestSupport
@testable import NewsCore

final class DecodingTests: XCTestCase {
    func decodeSummary(_ object: [String: Any]) throws -> ArticleSummary {
        try HCGJSON.makeDecoder().decode(ArticleSummary.self, from: JSONFixture.data(object))
    }

    func testSummaryDecodesTolerantly() throws {
        var object = JSONFixture.summary(id: "a1")
        object["id"] = 42                                  // numeric id
        object["editorialType"] = "Feature"                // unknown type kept verbatim
        object["image"] = ["url": 5]                       // malformed image omitted, article kept
        object["publishedAt"] = "2026-11-03 10:15:00+00"   // Postgres-style timestamp
        let summary = try decodeSummary(object)
        XCTAssertEqual(summary.id, ArticleID("42"))
        XCTAssertEqual(summary.editorialType, .other("Feature"))
        XCTAssertEqual(summary.editorialType?.label, "Feature")
        XCTAssertNil(summary.image)
        XCTAssertNotNil(summary.publishedAt)
        XCTAssertEqual(summary.access, .public, "absent access means not marked restricted")
    }

    func testEditorialTypesPreserved() {
        XCTAssertEqual(EditorialType(rawValue: "News").label, "News")
        XCTAssertEqual(EditorialType(rawValue: "analysis").label, "Analysis")
        XCTAssertEqual(EditorialType(rawValue: "Opinion").label, "Opinion")
        XCTAssertEqual(EditorialType(rawValue: "commentary"), .opinion)
    }

    func testShareableURLOnlyForHCGHTTPS() throws {
        var object = JSONFixture.summary(id: "a1")
        XCTAssertNotNil(try decodeSummary(object).shareableURL)
        object["canonicalUrl"] = "https://evil.example/hakmicapitalgroup.com"
        XCTAssertNil(try decodeSummary(object).shareableURL)
        object["canonicalUrl"] = "http://news.hakmicapitalgroup.com/x"
        XCTAssertNil(try decodeSummary(object).shareableURL)
        object["canonicalUrl"] = "https://news.hakmicapitalgroup.com.evil.example/x"
        XCTAssertNil(try decodeSummary(object).shareableURL)
    }

    func testDisclosuresComeFromVerifiedAuthorDataOnly() throws {
        let disclosure: [String: Any] = ["id": "d1", "authorID": "author-verified-1", "text": "Fictional disclosure text supplied by the backend.", "kind": "political-affiliation"]
        let withDisclosure = try decodeSummary(JSONFixture.summary(id: "a1", authors: [
            ["id": "author-verified-1", "name": "Yasin Ludvigsen Hakmi", "disclosures": [disclosure]],
        ]))
        XCTAssertEqual(withDisclosure.disclosures.map(\.text), ["Fictional disclosure text supplied by the backend."])

        // Same display name, different (unverified) identity, no backend disclosure:
        // the app must not invent or copy a disclosure by name.
        let sameNameOtherID = try decodeSummary(JSONFixture.summary(id: "a2", authors: [
            ["id": "someone-else", "name": "Yasin Ludvigsen Hakmi"],
        ]))
        XCTAssertTrue(sameNameOtherID.disclosures.isEmpty)
    }

    func testArticleBodyAsBlocks() throws {
        var object = JSONFixture.summary(id: "a1")
        object["body"] = ["format": "blocks", "blocks": [
            ["type": "heading", "level": 2, "text": "Heading"],
            ["type": "paragraph", "html": "Text with <a href=\"https://example.org\">a source</a>"],
            ["type": "paragraph", "text": "<b>literal</b>"],
            ["type": "list", "ordered": true, "items": ["One", "Two"]],
            ["type": "quote", "text": "Quoted", "attribution": "Someone"],
            ["type": "image", "image": ["url": "https://news.hakmicapitalgroup.com/i.jpg", "caption": "Cap", "credit": "Cred"]],
            ["type": "embed", "url": "https://social.example/post/1"],
            ["type": "poll", "question": "unsupported"],
            ["type": "divider"],
        ]]
        object["sources"] = [
            ["title": "Official report", "url": "https://example.org/report.pdf", "publisher": "Example Agency"],
            ["title": "Bad link", "url": "javascript:alert(1)"],
        ]
        let response = try HCGJSON.makeDecoder().decode(ArticleResponse.self, from: JSONFixture.data(object))
        let article = response.article(baseURL: URL(string: "https://news.hakmicapitalgroup.com"))
        XCTAssertEqual(article.blocks.count, 8, "unknown block types are skipped")
        guard case .paragraph(let literal) = article.blocks[2] else { return XCTFail() }
        XCTAssertEqual(literal.plainText, "<b>literal</b>", "plain text fields are never parsed as HTML")
        XCTAssertEqual(article.blocks[6], .embedNotice(host: "social.example"))
        XCTAssertEqual(article.sources.count, 2)
        XCTAssertNotNil(article.sources[0].url)
        XCTAssertNil(article.sources[1].url, "non-web source links are dropped")
    }

    func testArticleBodyAsHTML() throws {
        var object = JSONFixture.summary(id: "a1")
        object["body"] = ["format": "html", "html": "<p>One</p><script>x()</script><p>Two</p>"]
        let response = try HCGJSON.makeDecoder().decode(ArticleResponse.self, from: JSONFixture.data(object))
        XCTAssertEqual(response.article(baseURL: nil).blocks.count, 2)
    }
}

final class PublicationRulesTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func make(_ id: String, status: String? = "published", publishedOffset: TimeInterval? = -3600,
              access: AccessLevel = .public, breaking: BreakingFlag? = nil, headline: String = "Headline") -> ArticleSummary {
        ArticleSummary(id: ArticleID(id), headline: headline, publishedAt: publishedOffset.map { now.addingTimeInterval($0) },
                       breaking: breaking, access: access, status: status)
    }

    func testDraftsPrivateScheduledAndUndatedAreHidden() {
        let items = [
            make("ok"),
            make("draft", status: "draft"),
            make("private", status: "private"),
            make("scheduled", publishedOffset: 3600),
            make("undated", publishedOffset: nil),
            make("unknownAccess", access: .unknown("internal")),
            make("blank", headline: "   "),
            make("restricted", access: .restricted),
            make("ok"),   // duplicate id
        ]
        XCTAssertEqual(PublicationVisibility.filter(items, now: now).map(\.id.rawValue), ["ok", "restricted"])
    }

    func testSmallClockSkewIsTolerated() {
        XCTAssertEqual(PublicationVisibility.decision(for: make("a", publishedOffset: 120), now: now), .visible)
    }

    func testBreakingRequiresExplicitActiveFlag() {
        let items = [
            make("recent-not-flagged", publishedOffset: -10),
            make("flag-inactive", breaking: BreakingFlag(active: false)),
            make("expired", breaking: BreakingFlag(active: true, expiresAt: now.addingTimeInterval(-1))),
            make("breaking", breaking: BreakingFlag(active: true, expiresAt: now.addingTimeInterval(600))),
            make("draft-breaking", status: "draft", breaking: BreakingFlag(active: true)),
        ]
        XCTAssertEqual(BreakingNewsRule.select(from: [items], now: now).map(\.id.rawValue), ["breaking"])
    }

    func testBreakingIsLimitedAndNewestFirst() {
        let items = (0..<8).map { make("b\($0)", publishedOffset: -Double($0) * 60, breaking: BreakingFlag(active: true)) }
        let selected = BreakingNewsRule.select(from: [items, items], now: now)
        XCTAssertEqual(selected.map(\.id.rawValue), ["b0", "b1", "b2", "b3", "b4"])
    }

    func testLocalSearchIsDiacriticAndCaseInsensitive() {
        let a = ArticleSummary(id: ArticleID("1"), headline: "Stortinget behandler budsjettet", publishedAt: now)
        let b = ArticleSummary(id: ArticleID("2"), headline: "Analyse: Europe after the vote", publishedAt: now)
        XCTAssertEqual(LocalArticleSearch.search("STORTINGET", in: [a, b]).map(\.id.rawValue), ["1"])
        XCTAssertEqual(LocalArticleSearch.search("europe vote", in: [a, b]).map(\.id.rawValue), ["2"])
        XCTAssertTrue(LocalArticleSearch.search("   ", in: [a, b]).isEmpty)
    }
}
