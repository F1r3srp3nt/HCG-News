import Foundation
import NewsCore

/// One editable block of an article body.
public struct EditableBodyBlock: Equatable, Sendable, Identifiable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case paragraph, heading, subheading, bulletList, numberedList, quote, image, divider

        public var title: String {
            switch self {
            case .paragraph: "Paragraph"
            case .heading: "Heading"
            case .subheading: "Subheading"
            case .bulletList: "Bulleted list"
            case .numberedList: "Numbered list"
            case .quote: "Quotation"
            case .image: "Image"
            case .divider: "Divider"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    /// Text with **bold**, *italic* and [link](https://…) markup. One list item per line.
    public var text: String
    /// Quote attribution.
    public var attribution: String
    public var imageURL: String
    public var altText: String
    public var caption: String
    public var credit: String

    public init(id: UUID = UUID(), kind: Kind, text: String = "", attribution: String = "", imageURL: String = "",
                altText: String = "", caption: String = "", credit: String = "") {
        self.id = id; self.kind = kind; self.text = text; self.attribution = attribution
        self.imageURL = imageURL; self.altText = altText; self.caption = caption; self.credit = credit
    }
}

/// Converts between the publication's article HTML (written by the website's rich-text
/// editor) and editable blocks.
///
/// The app only offers body editing when the conversion is lossless for that article:
/// the HTML uses only plain structural tags, and re-encoding the blocks renders exactly
/// the same content. Otherwise the body stays read-only in the app (other fields remain
/// editable) and is never sent back, so nothing the app can't represent is lost.
public enum ArticleBodyCodec {
    public enum Decision: Equatable, Sendable {
        case editable([EditableBodyBlock])
        case readOnly(reason: String)
    }

    static let allowedTags: Set<String> = [
        "p", "h2", "h3", "strong", "b", "em", "i", "a", "ul", "ol", "li", "blockquote", "cite",
        "figure", "figcaption", "img", "hr", "br", "span",
    ]

    public static func decode(_ html: String, publicationURL: URL) -> Decision {
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .editable([]) }
        if let problem = structuralProblem(html) { return .readOnly(reason: problem) }
        let parser = HTMLContentParser(baseURL: publicationURL)
        let original = parser.parse(html)
        var blocks: [EditableBodyBlock] = []
        for block in original {
            switch block {
            case .heading(let level, let text):
                blocks.append(EditableBodyBlock(kind: level <= 2 ? .heading : .subheading, text: markup(text)))
            case .paragraph(let text):
                blocks.append(EditableBodyBlock(kind: .paragraph, text: markup(text)))
            case .list(let ordered, let items):
                if items.contains(where: { $0.level > 0 }) { return .readOnly(reason: "The body has nested lists, which the app can't edit yet.") }
                blocks.append(EditableBodyBlock(kind: ordered ? .numberedList : .bulletList,
                                                text: items.map { markup($0.text) }.joined(separator: "\n")))
            case .quote(let paragraphs, let attribution):
                if paragraphs.count > 1 { return .readOnly(reason: "The body has multi-paragraph quotations, which the app can't edit yet.") }
                blocks.append(EditableBodyBlock(kind: .quote, text: paragraphs.first.map(markup) ?? "", attribution: attribution ?? ""))
            case .image(let image):
                blocks.append(EditableBodyBlock(kind: .image, imageURL: image.url.absoluteString, altText: image.alt ?? "",
                                                caption: image.caption ?? "", credit: image.credit ?? ""))
            case .divider:
                blocks.append(EditableBodyBlock(kind: .divider))
            default:
                return .readOnly(reason: "The body contains embedded or special content the app can't edit.")
            }
        }
        // Lossless check: re-encoding must render exactly what the original renders.
        guard parser.parse(encode(blocks)) == original else {
            return .readOnly(reason: "The body has formatting the app can't reproduce exactly.")
        }
        return .editable(blocks)
    }

    /// Tags and attributes the app can't reproduce make the body read-only.
    static func structuralProblem(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<\\s*/?\\s*([a-zA-Z][a-zA-Z0-9]*)([^>]*)>") else { return "unreadable" }
        let ns = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            guard allowedTags.contains(name) else { return "The body contains <\(name)> content the app can't edit." }
            let attributes = ns.substring(with: match.range(at: 2)).lowercased()
            if attributes.contains("style=") || attributes.contains("data-") || attributes.contains("id=") {
                return "The body has styled content the app can't edit."
            }
            if attributes.contains("class="), name != "span" { return "The body has styled content the app can't edit." }
            if name == "img", attributes.contains("width=") || attributes.contains("height=") {
                return "The body has sized images the app can't edit."
            }
        }
        return nil
    }

    /// Clean HTML in the shape the website's editor writes.
    public static func encode(_ blocks: [EditableBodyBlock]) -> String {
        var out: [String] = []
        for block in blocks {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch block.kind {
            case .paragraph:
                if !text.isEmpty { out.append("<p>\(inlineHTML(text))</p>") }
            case .heading:
                if !text.isEmpty { out.append("<h2>\(inlineHTML(text))</h2>") }
            case .subheading:
                if !text.isEmpty { out.append("<h3>\(inlineHTML(text))</h3>") }
            case .bulletList, .numberedList:
                let items = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                guard !items.isEmpty else { continue }
                let tag = block.kind == .numberedList ? "ol" : "ul"
                out.append("<\(tag)>" + items.map { "<li><p>\(inlineHTML($0))</p></li>" }.joined() + "</\(tag)>")
            case .quote:
                guard !text.isEmpty else { continue }
                let attribution = block.attribution.trimmingCharacters(in: .whitespacesAndNewlines)
                out.append("<blockquote><p>\(inlineHTML(text))</p>" + (attribution.isEmpty ? "" : "<cite>\(escape(attribution))</cite>") + "</blockquote>")
            case .image:
                let src = block.imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: src), url.scheme?.lowercased() == "https" else { continue }
                let caption = block.caption.trimmingCharacters(in: .whitespacesAndNewlines)
                let credit = block.credit.trimmingCharacters(in: .whitespacesAndNewlines)
                let img = "<img src=\"\(escape(url.absoluteString))\" alt=\"\(escape(block.altText.trimmingCharacters(in: .whitespacesAndNewlines)))\">"
                if caption.isEmpty && credit.isEmpty {
                    out.append(img)
                } else {
                    out.append("<figure>\(img)<figcaption>\(escape(caption))"
                               + (credit.isEmpty ? "" : "<span class=\"credit\">\(escape(credit))</span>") + "</figcaption></figure>")
                }
            case .divider:
                out.append("<hr>")
            }
        }
        return out.joined()
    }

    /// Problems to fix before the body can be saved (e.g. images without alt text).
    public static func problems(_ blocks: [EditableBodyBlock]) -> [String] {
        var problems: [String] = []
        for (index, block) in blocks.enumerated() where block.kind == .image {
            let src = block.imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if URL(string: src)?.scheme?.lowercased() != "https" { problems.append("Image \(index + 1): choose an image from the media library.") }
            if block.altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append("Image \(index + 1): add alt text describing the image.") }
        }
        return problems
    }

    // MARK: Inline

    static func markup(_ text: InlineText) -> String {
        var out = ""
        for run in text.runs {
            var piece = run.text
            if run.bold { piece = "**\(piece)**" }
            if run.italic { piece = "*\(piece)*" }
            if let link = run.link { piece = "[\(piece)](\(link.absoluteString))" }
            out += piece
        }
        return out
    }

    static func inlineHTML(_ markup: String) -> String {
        let inline = markupRuns(markup)
        return inline.runs.map { run in
            var piece = escape(run.text).replacingOccurrences(of: "\n", with: "<br>")
            if run.bold { piece = "<strong>\(piece)</strong>" }
            if run.italic { piece = "<em>\(piece)</em>" }
            if let link = run.link {
                piece = "<a href=\"\(escape(link.absoluteString))\" target=\"_blank\" rel=\"noopener noreferrer nofollow\">\(piece)</a>"
            }
            return piece
        }.joined()
    }

    /// The same markup the local draft editor uses.
    static func markupRuns(_ text: String) -> InlineText {
        var runs: [InlineRun] = []
        var bold = false, italic = false
        var buffer = ""
        let chars = Array(text)
        var i = 0
        func flush() { if !buffer.isEmpty { runs.append(InlineRun(buffer, bold: bold, italic: italic)); buffer = "" } }
        while i < chars.count {
            let c = chars[i]
            if c == "*", i + 1 < chars.count, chars[i + 1] == "*" { flush(); bold.toggle(); i += 2; continue }
            if c == "*" { flush(); italic.toggle(); i += 1; continue }
            if c == "[", let close = chars[(i + 1)...].firstIndex(of: "]"), close + 1 < chars.count, chars[close + 1] == "(",
               let end = matchingParen(chars, from: close + 1) {
                flush()
                let label = markupRuns(String(chars[(i + 1)..<close]))
                let url = URL(string: String(chars[(close + 2)..<end])).flatMap(LinkPolicy.allowedExternalURL)
                for run in label.runs {
                    runs.append(InlineRun(run.text, bold: bold || run.bold, italic: italic || run.italic, link: url))
                }
                i = end + 1
                continue
            }
            buffer.append(c)
            i += 1
        }
        flush()
        return InlineText(runs)
    }

    static func matchingParen(_ chars: [Character], from open: Int) -> Int? {
        var depth = 0
        var j = open
        while j < chars.count {
            if chars[j] == "(" { depth += 1 }
            if chars[j] == ")" { depth -= 1; if depth == 0 { return j } }
            j += 1
        }
        return nil
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
