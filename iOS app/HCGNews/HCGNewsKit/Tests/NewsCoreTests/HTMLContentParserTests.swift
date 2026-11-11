import XCTest
@testable import NewsCore

final class HTMLContentParserTests: XCTestCase {
    let base = URL(string: "https://news.hakmicapitalgroup.com/articles/test")!
    var parser: HTMLContentParser { HTMLContentParser(baseURL: base) }

    func testParagraphsHeadingsAndInlineFormatting() {
        let blocks = parser.parse("""
        <h2>Section  heading</h2>
        <p>First <strong>bold</strong> and <em>italic</em>
           text.</p>
        <p>Second paragraph.</p>
        """)
        XCTAssertEqual(blocks.count, 3)
        guard case .heading(let level, let heading) = blocks[0] else { return XCTFail("expected heading") }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(heading.plainText, "Section heading")
        guard case .paragraph(let p) = blocks[1] else { return XCTFail("expected paragraph") }
        XCTAssertEqual(p.plainText, "First bold and italic text.")
        XCTAssertTrue(p.runs.contains { $0.text == "bold" && $0.bold })
        XCTAssertTrue(p.runs.contains { $0.text == "italic" && $0.italic })
    }

    func testH1IsDemotedAndDeepHeadingsClamped() {
        let blocks = parser.parse("<h1>A</h1><h6>B</h6>")
        XCTAssertEqual(blocks, [.heading(level: 2, text: InlineText(plain: "A")), .heading(level: 4, text: InlineText(plain: "B"))])
    }

    func testListsIncludingNestedAndParagraphsInItems() {
        let blocks = parser.parse("""
        <ul><li>One</li><li><p>Two</p><ul><li>Two A</li></ul></li></ul>
        <ol><li>First</li><li>Second</li></ol>
        """)
        XCTAssertEqual(blocks.count, 2)
        guard case .list(let ordered, let items) = blocks[0] else { return XCTFail("expected list") }
        XCTAssertFalse(ordered)
        XCTAssertEqual(items.map(\.text.plainText), ["One", "Two", "Two A"])
        XCTAssertEqual(items.map(\.level), [0, 0, 1])
        guard case .list(let ordered2, let items2) = blocks[1] else { return XCTFail("expected list") }
        XCTAssertTrue(ordered2)
        XCTAssertEqual(items2.count, 2)
    }

    func testBlockquoteWithAttribution() {
        let blocks = parser.parse("<blockquote><p>We will publish the figures.</p><footer>— A fictional spokesperson</footer></blockquote>")
        XCTAssertEqual(blocks, [.quote(paragraphs: [InlineText(plain: "We will publish the figures.")], attribution: "A fictional spokesperson")])
    }

    func testFigureWithCaptionAndCredit() {
        let blocks = parser.parse("""
        <figure><img src="/media/test.jpg" alt="A test image" width="1200" height="800">
        <figcaption>Caption text. <span class="credit">Photo: Test Photographer</span></figcaption></figure>
        """)
        XCTAssertEqual(blocks.count, 1)
        guard case .image(let image) = blocks[0] else { return XCTFail("expected image") }
        XCTAssertEqual(image.url.absoluteString, "https://news.hakmicapitalgroup.com/media/test.jpg")
        XCTAssertEqual(image.alt, "A test image")
        XCTAssertEqual(image.caption, "Caption text.")
        XCTAssertEqual(image.credit, "Photo: Test Photographer")
        XCTAssertEqual(image.aspectRatio ?? 0, 1.5, accuracy: 0.001)
    }

    func testLinksAllowHttpsAndMailtoAndResolveRelative() {
        let blocks = parser.parse(#"<p><a href="https://example.org/report">Report</a>, <a href="/about">About</a>, <a href="mailto:desk@example.org">Mail</a></p>"#)
        guard case .paragraph(let p) = blocks.first else { return XCTFail() }
        XCTAssertEqual(p.links.map(\.absoluteString), [
            "https://example.org/report", "https://news.hakmicapitalgroup.com/about", "mailto:desk@example.org",
        ])
    }

    func testDangerousLinksAreDroppedButTextKept() {
        let html = #"<p><a href="javascript:alert(1)">one</a> <a href="java&#x09;script:alert(1)">two</a> <a href="data:text/html,x">three</a> <a href="vbscript:x">four</a> <a href="file:///etc/passwd">five</a></p>"#
        guard case .paragraph(let p) = parser.parse(html).first else { return XCTFail() }
        XCTAssertEqual(p.plainText, "one two three four five")
        XCTAssertTrue(p.links.isEmpty, "no executable or local links may survive: \(p.links)")
    }

    func testScriptsStylesFormsAndHandlersNeverSurvive() {
        let html = """
        <p onclick="steal()">Visible <img src="https://x.example/a.png" onerror="steal()"></p>
        <script>document.write('<p>injected</p>')</script>
        <style>p { display:none }</style>
        <form action="https://evil.example"><input name="q"><button>Go</button></form>
        <svg><text>svg text</text></svg>
        <noscript><p>noscript text</p></noscript>
        <template><p>template text</p></template>
        <p>After</p>
        """
        let blocks = parser.parse(html)
        let text = blocks.map { block -> String in
            switch block {
            case .paragraph(let t): return t.plainText
            default: return ""
            }
        }.joined(separator: "|")
        XCTAssertFalse(text.contains("injected"))
        XCTAssertFalse(text.contains("display"))
        XCTAssertFalse(text.contains("Go"))
        XCTAssertFalse(text.contains("svg text"))
        XCTAssertFalse(text.contains("noscript"))
        XCTAssertFalse(text.contains("template"))
        XCTAssertTrue(text.contains("Visible"))
        XCTAssertTrue(text.contains("After"))
    }

    func testEmbedsBecomeNoticesAndAreNotLoaded() {
        let blocks = parser.parse(#"<p>Before</p><iframe src="https://video.example.com/embed/1"><p>fallback</p></iframe><video src="https://cdn.example/v.mp4"></video><p>After</p>"#)
        XCTAssertEqual(blocks, [
            .paragraph(InlineText(plain: "Before")),
            .embedNotice(host: "video.example.com"),
            .embedNotice(host: "cdn.example"),
            .paragraph(InlineText(plain: "After")),
        ])
    }

    func testInsecureImagesAreDropped() {
        XCTAssertTrue(parser.parse(#"<img src="http://insecure.example/a.jpg">"#).isEmpty)
        XCTAssertTrue(parser.parse(#"<img src="data:image/png;base64,AAAA">"#).isEmpty)
    }

    func testEntitiesAndNorwegianCharacters() {
        guard case .paragraph(let p) = parser.parse("<p>Fremskrittspartiet &amp; FpU &mdash; &#216;stlandet, Tr&oslash;ndelag &aring; &#x2019;</p>").first else { return XCTFail() }
        XCTAssertEqual(p.plainText, "Fremskrittspartiet & FpU — Østlandet, Trøndelag å ’")
    }

    func testLineBreaksAndPreformatted() {
        let blocks = parser.parse("<p>Line one<br>Line two</p><pre>a  b\n c</pre>")
        guard case .paragraph(let p) = blocks[0], case .paragraph(let pre) = blocks[1] else { return XCTFail() }
        XCTAssertEqual(p.plainText, "Line one\nLine two")
        XCTAssertEqual(pre.plainText, "a  b\n c")
        XCTAssertTrue(pre.runs.allSatisfy(\.code))
    }

    func testMalformedHTMLDoesNotCrashAndKeepsText() {
        let inputs = ["<p>Unclosed <b>bold", "<<<>>>", "<a href='x", "</p></div>text", "<p>a</p", "&#xFFFFFFFF; &#0; &bogus;", "<!-- unterminated"]
        for input in inputs {
            _ = parser.parse(input)
        }
        guard case .paragraph(let p) = parser.parse("<p>Unclosed <b>bold").first else { return XCTFail() }
        XCTAssertEqual(p.plainText, "Unclosed bold")
    }

    func testInlineParsingFlattensBlocks() {
        let inline = parser.parseInline("<p>One <a href=\"https://example.org\">link</a></p><p>Two</p>")
        XCTAssertEqual(inline.plainText, "One link Two")
        XCTAssertEqual(inline.links.count, 1)
    }

    func testBlockLimitIsEnforced() {
        let html = String(repeating: "<p>x</p>", count: 50)
        let limited = HTMLContentParser(baseURL: nil, limits: .init(maxInputScalars: 1_000_000, maxBlocks: 10))
        XCTAssertEqual(limited.parse(html).count, 10)
    }

    func testDividersCollapse() {
        XCTAssertEqual(parser.parse("<hr><hr><p>x</p>"), [.divider, .paragraph(InlineText(plain: "x"))])
    }
}
