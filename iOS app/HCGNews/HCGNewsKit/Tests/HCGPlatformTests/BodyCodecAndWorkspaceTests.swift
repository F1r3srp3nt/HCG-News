import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import HCGTestSupport
import NewsCore
@testable import HCGPlatform

final class ArticleBodyCodecTests: XCTestCase {
    let base = URL(string: "https://news.hakmicapitalgroup.com")!

    func testTypicalEditorHTMLRoundTripsLosslessly() throws {
        let html = """
        <h2>Background</h2><p>Plain, <strong>bold</strong>, <em>italic</em> and <a target="_blank" rel="noopener noreferrer nofollow" href="https://www.ssb.no/x">a link</a>.</p>\
        <ul><li><p>One</p></li><li><p>Two</p></li></ul><blockquote><p>A quote.</p></blockquote>\
        <img src="https://qggdyzoydveafkmjgkpq.supabase.co/storage/v1/object/sign/hcg-news-media/a.jpg?token=t" alt="Alt text"><hr><h3>Next</h3><p>End.</p>
        """
        guard case .editable(let blocks) = ArticleBodyCodec.decode(html, publicationURL: base) else { return XCTFail("not editable") }
        XCTAssertEqual(blocks.map(\.kind), [.heading, .paragraph, .bulletList, .quote, .image, .divider, .subheading, .paragraph])
        XCTAssertEqual(blocks[1].text, "Plain, **bold**, *italic* and [a link](https://www.ssb.no/x).")
        XCTAssertEqual(blocks[2].text, "One\nTwo")
        let parser = HTMLContentParser(baseURL: base)
        XCTAssertEqual(parser.parse(ArticleBodyCodec.encode(blocks)), parser.parse(html))
    }

    func testContentTheAppCantReproduceIsReadOnly() {
        let cases = [
            "<p>Text</p><iframe src=\"https://www.youtube.com/embed/x\"></iframe>",
            "<p style=\"text-align:center\">Centred</p>",
            "<h4>Deep heading</h4>",
            "<p>Literal *asterisks* typed as text</p>".replacingOccurrences(of: "*asterisks*", with: "&#42;a&#42;"),
            "<ul><li><p>One</p><ul><li><p>Nested</p></li></ul></li></ul>",
            "<table><tr><td>x</td></tr></table>",
        ]
        for html in cases {
            guard case .readOnly = ArticleBodyCodec.decode(html, publicationURL: base) else { return XCTFail("editable: \(html)") }
        }
    }

    func testEncodingEscapesTextAndDropsUnsafeImages() {
        let blocks = [EditableBodyBlock(kind: .paragraph, text: "a < b & \"c\""),
                      EditableBodyBlock(kind: .image, imageURL: "http://insecure.example/x.jpg", altText: "x"),
                      EditableBodyBlock(kind: .image, imageURL: "https://x.example/y.jpg", altText: "Alt", caption: "Cap", credit: "Cred")]
        let html = ArticleBodyCodec.encode(blocks)
        XCTAssertTrue(html.hasPrefix("<p>a &lt; b &amp; &quot;c&quot;</p>"))
        XCTAssertFalse(html.contains("insecure"))
        XCTAssertTrue(html.contains("<figcaption>Cap<span class=\"credit\">Cred</span></figcaption>"))
        XCTAssertEqual(ArticleBodyCodec.problems([EditableBodyBlock(kind: .image, imageURL: "https://x.example/y.jpg")]),
                       ["Image 1: add alt text describing the image."])
    }
}

final class WorkspaceServiceTests: XCTestCase {
    func service(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) async throws -> (HCGWorkspaceService, FakeTransport) {
        let transport = FakeTransport { request in request.path == "/auth/v1/token" ? (200, tokenResponse()) : handler(request) }
        let client = PlatformClient(configuration: testPlatform, transport: transport, userAgent: "t")
        let account = HCGAccountSession(client: client, store: MemorySessionStore(), now: { fixedNow })
        _ = try await account.signIn(email: "a@b.c", password: "p")
        return (HCGWorkspaceService(client: client, caller: AuthorizedCaller(account: account)), transport)
    }

    func testDirectoryIsReadFromTheWebsiteWithTheBearerToken() async throws {
        let (svc, transport) = try await service { _ in
            (200, json(["roles": ["owner"], "workspaces": [["id": "erp", "permitted": true, "available": true],
                                                         ["id": "ceo_suite", "permitted": false, "available": true]],
                        "integration": ["handoff": "v2", "version": 2]]))
        }
        let directory = try await svc.directory(now: fixedNow)
        XCTAssertEqual(directory.workspace("erp")?.permitted, true)
        XCTAssertEqual(directory.workspace("ceo_suite")?.permitted, false)
        XCTAssertEqual(directory.workspace("ceo_suite")?.displayTitle, "Executive Control Center")
        XCTAssertEqual(directory.handoffVersion, 2)
        XCTAssertEqual(directory.workspace("erp")?.handoffTarget, "/erp")
        XCTAssertEqual(directory.workspace("ceo_suite")?.handoffTarget, "/control-panel")
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.url?.host, "beta.hakmicapitalgroup.com")
        XCTAssertEqual(request.path, "/api/public/mobile/workspaces")
        XCTAssertEqual(request.bearer, "access-1")
    }

    func testHandoffOnlyOpensHCGLinksAndReportsDenial() async throws {
        let (svc, transport) = try await service { _ in (200, json(["url": "https://beta.hakmicapitalgroup.com/erp#code", "target": "erp"])) }
        let handoff = try await svc.handoff(target: "/erp")
        XCTAssertEqual(handoff.url.absoluteString, "https://beta.hakmicapitalgroup.com/erp#code")
        XCTAssertEqual(transport.requests.last?.bodyObject["target"] as? String, "/erp")

        transport.setHandler { r in r.path == "/auth/v1/token" ? (200, tokenResponse()) : (200, json(["url": "https://evil.example/erp#code"])) }
        do { _ = try await svc.handoff(target: "erp"); XCTFail() } catch { XCTAssertNotEqual(error, .denied) }

        transport.setHandler { r in r.path == "/auth/v1/token" ? (200, tokenResponse()) : (403, json(["error": "forbidden"])) }
        do { _ = try await svc.handoff(target: "erp"); XCTFail() } catch { XCTAssertEqual(error, .denied) }
    }
}
