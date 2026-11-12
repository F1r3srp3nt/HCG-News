import Foundation

// Converts untrusted article HTML into inert native `ContentBlock`s.
//
// Security model: an allow-list *output* model. The parser never renders HTML;
// it only extracts text, a fixed set of structures (headings, paragraphs, lists,
// quotations, figures, dividers) and http(s)/mailto links. Scripts, styles,
// event handlers, forms, iframes, objects and SVG are never carried over:
// their content is dropped, and embeds become a visible notice instead of
// being loaded. Attributes other than href/src/alt/width/height/class are ignored.

public struct HTMLContentParser: Sendable {
    public struct Limits: Sendable {
        public var maxInputScalars: Int
        public var maxBlocks: Int
        public init(maxInputScalars: Int = 1_500_000, maxBlocks: Int = 3_000) {
            self.maxInputScalars = maxInputScalars
            self.maxBlocks = maxBlocks
        }
    }

    public let baseURL: URL?
    public let limits: Limits

    public init(baseURL: URL?, limits: Limits = Limits()) {
        self.baseURL = baseURL
        self.limits = limits
    }

    /// Parses an article body.
    public func parse(_ html: String) -> [ContentBlock] {
        var builder = BlockBuilder(baseURL: baseURL, maxBlocks: limits.maxBlocks)
        for token in HTMLTokenizer.tokenize(html, maxScalars: limits.maxInputScalars) {
            builder.consume(token)
            if builder.isFull { break }
        }
        return builder.finish()
    }

    /// Parses an inline fragment (e.g. a paragraph's `html` field). Block
    /// structure is flattened; only inline formatting and links are kept.
    public func parseInline(_ html: String) -> InlineText {
        let blocks = parse(html)
        var runs: [InlineRun] = []
        for block in blocks {
            let text: InlineText?
            switch block {
            case .paragraph(let t), .heading(_, let t): text = t
            case .list(_, let items): text = InlineText(items.flatMap(\.text.runs))
            case .quote(let paragraphs, _): text = InlineText(paragraphs.flatMap(\.runs))
            default: text = nil
            }
            guard let text, !text.isBlank else { continue }
            if !runs.isEmpty { runs.append(InlineRun(" ")) }
            runs.append(contentsOf: text.runs)
        }
        return InlineText(InlineTextNormaliser.merge(runs))
    }
}

// MARK: - Tokenizer

enum HTMLToken: Equatable {
    case start(name: String, attributes: [String: String], selfClosing: Bool)
    case end(name: String)
    case text(String)
}

enum HTMLTokenizer {
    /// Elements whose content is raw text and must be skipped wholesale.
    static let rawTextElements: Set<String> = [
        "script", "style", "textarea", "title", "xmp", "noscript", "noembed", "noframes", "iframe",
    ]

    static func tokenize(_ html: String, maxScalars: Int) -> [HTMLToken] {
        var scalars = Array(html.unicodeScalars)
        if scalars.count > maxScalars { scalars = Array(scalars.prefix(maxScalars)) }
        var tokens: [HTMLToken] = []
        var text = String.UnicodeScalarView()
        var i = 0
        let n = scalars.count

        func flushText() {
            guard !text.isEmpty else { return }
            tokens.append(.text(HTMLEntities.decode(String(text))))
            text = String.UnicodeScalarView()
        }
        func isNameStart(_ s: Unicode.Scalar) -> Bool {
            (s >= "a" && s <= "z") || (s >= "A" && s <= "Z")
        }
        func isNameChar(_ s: Unicode.Scalar) -> Bool {
            isNameStart(s) || (s >= "0" && s <= "9") || s == "-" || s == ":" || s == "_"
        }
        func isSpace(_ s: Unicode.Scalar) -> Bool {
            s == " " || s == "\n" || s == "\t" || s == "\r" || s == "\u{0C}"
        }
        func matches(_ literal: String, at index: Int, caseInsensitive: Bool = false) -> Bool {
            let lit = Array(literal.unicodeScalars)
            guard index + lit.count <= n else { return false }
            for k in 0..<lit.count {
                var a = scalars[index + k], b = lit[k]
                if caseInsensitive {
                    a = Unicode.Scalar(String(a).lowercased().unicodeScalars.first!.value) ?? a
                    b = Unicode.Scalar(String(b).lowercased().unicodeScalars.first!.value) ?? b
                }
                if a != b { return false }
            }
            return true
        }
        func skip(past literal: String, from index: Int, caseInsensitive: Bool = false) -> Int {
            var j = index
            while j < n {
                if matches(literal, at: j, caseInsensitive: caseInsensitive) { return j + literal.unicodeScalars.count }
                j += 1
            }
            return n
        }

        while i < n {
            let c = scalars[i]
            guard c == "<", i + 1 < n else {
                text.append(c)
                i += 1
                continue
            }
            let next = scalars[i + 1]
            if matches("<!--", at: i) {
                flushText()
                i = skip(past: "-->", from: i + 4)
            } else if next == "!" || next == "?" {
                flushText()
                i = skip(past: ">", from: i + 2)
            } else if next == "/" {
                flushText()
                var j = i + 2
                var name = String.UnicodeScalarView()
                while j < n, isNameChar(scalars[j]) { name.append(scalars[j]); j += 1 }
                i = skip(past: ">", from: j)
                if !name.isEmpty { tokens.append(.end(name: String(name).lowercased())) }
            } else if isNameStart(next) {
                flushText()
                var j = i + 1
                var nameScalars = String.UnicodeScalarView()
                while j < n, isNameChar(scalars[j]) { nameScalars.append(scalars[j]); j += 1 }
                let name = String(nameScalars).lowercased()
                var attributes: [String: String] = [:]
                var selfClosing = false
                // Attributes.
                while j < n {
                    while j < n, isSpace(scalars[j]) { j += 1 }
                    guard j < n else { break }
                    if scalars[j] == ">" { j += 1; break }
                    if scalars[j] == "/" {
                        if j + 1 < n, scalars[j + 1] == ">" { selfClosing = true; j += 2; break }
                        j += 1
                        continue
                    }
                    var attrName = String.UnicodeScalarView()
                    while j < n, !isSpace(scalars[j]), scalars[j] != "=", scalars[j] != ">", scalars[j] != "/" {
                        attrName.append(scalars[j]); j += 1
                    }
                    while j < n, isSpace(scalars[j]) { j += 1 }
                    var value = String.UnicodeScalarView()
                    if j < n, scalars[j] == "=" {
                        j += 1
                        while j < n, isSpace(scalars[j]) { j += 1 }
                        if j < n, scalars[j] == "\"" || scalars[j] == "'" {
                            let quote = scalars[j]
                            j += 1
                            while j < n, scalars[j] != quote { value.append(scalars[j]); j += 1 }
                            if j < n { j += 1 }
                        } else {
                            while j < n, !isSpace(scalars[j]), scalars[j] != ">" { value.append(scalars[j]); j += 1 }
                        }
                    }
                    let key = String(attrName).lowercased()
                    if !key.isEmpty, attributes[key] == nil {
                        attributes[key] = HTMLEntities.decode(String(value))
                    }
                }
                i = j
                tokens.append(.start(name: name, attributes: attributes, selfClosing: selfClosing))
                if rawTextElements.contains(name), !selfClosing {
                    // Skip everything up to the matching close tag.
                    var k = i
                    while k < n {
                        if matches("</" + name, at: k, caseInsensitive: true) { break }
                        k += 1
                    }
                    i = k < n ? skip(past: ">", from: k) : n
                    tokens.append(.end(name: name))
                }
            } else {
                text.append(c)
                i += 1
            }
        }
        flushText()
        return tokens
    }
}

// MARK: - Entities

enum HTMLEntities {
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’", "sbquo": "‚",
        "ldquo": "“", "rdquo": "”", "bdquo": "„", "laquo": "«", "raquo": "»", "middot": "·",
        "bull": "•", "copy": "©", "reg": "®", "trade": "™", "deg": "°", "euro": "€", "pound": "£",
        "aelig": "æ", "AElig": "Æ", "oslash": "ø", "Oslash": "Ø", "aring": "å", "Aring": "Å",
        "auml": "ä", "Auml": "Ä", "ouml": "ö", "Ouml": "Ö", "uuml": "ü", "Uuml": "Ü", "eacute": "é",
        "Eacute": "É", "egrave": "è", "aacute": "á", "oacute": "ó", "iacute": "í", "uacute": "ú",
        "ntilde": "ñ", "ccedil": "ç", "szlig": "ß", "times": "×", "minus": "−", "shy": "\u{00AD}",
        "zwj": "\u{200D}", "zwnj": "\u{200C}", "thinsp": "\u{2009}", "ensp": "\u{2002}", "emsp": "\u{2003}",
    ]

    static func decode(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        result.reserveCapacity(string.count)
        var index = string.startIndex
        while index < string.endIndex {
            let ch = string[index]
            guard ch == "&",
                  let semicolon = string[index...].prefix(12).firstIndex(of: ";")
            else {
                result.append(ch)
                index = string.index(after: index)
                continue
            }
            let entity = String(string[string.index(after: index)..<semicolon])
            if let replacement = decodeEntity(entity) {
                result.append(replacement)
                index = string.index(after: semicolon)
            } else {
                result.append(ch)
                index = string.index(after: index)
            }
        }
        return result
    }

    private static func decodeEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#") {
            let body = entity.dropFirst()
            let value: UInt32?
            if body.hasPrefix("x") || body.hasPrefix("X") {
                value = UInt32(body.dropFirst(), radix: 16)
            } else {
                value = UInt32(body, radix: 10)
            }
            guard let value, value != 0, let scalar = Unicode.Scalar(value) else { return nil }
            // Drop control characters other than ordinary whitespace.
            if value < 0x20, value != 0x09, value != 0x0A, value != 0x0D { return "" }
            return String(Character(scalar))
        }
        return named[entity]
    }
}

// MARK: - Builder

enum InlineTextNormaliser {
    /// Merges adjacent runs with identical formatting.
    static func merge(_ runs: [InlineRun]) -> [InlineRun] {
        var merged: [InlineRun] = []
        for run in runs where !run.text.isEmpty {
            if var last = merged.last, last.sameStyle(as: run) {
                last.text += run.text
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    /// Trims leading/trailing whitespace of a block and spaces adjacent to line breaks.
    /// Preformatted text keeps its interior whitespace; only surrounding newlines are trimmed.
    static func trim(_ runs: [InlineRun], preformatted: Bool = false) -> [InlineRun] {
        var runs = merge(runs)
        if preformatted {
            if let first = runs.first {
                runs[0].text = String(first.text.drop(while: { $0 == "\n" }))
            }
            if let last = runs.last {
                var text = last.text
                while text.last == "\n" { text.removeLast() }
                runs[runs.count - 1].text = text
            }
            return runs.filter { !$0.text.isEmpty }
        }
        while let first = runs.first {
            let trimmed = String(first.text.drop(while: { $0 == " " || $0 == "\n" }))
            if trimmed.isEmpty { runs.removeFirst(); continue }
            runs[0].text = trimmed
            break
        }
        while let last = runs.last {
            var text = last.text
            while let c = text.last, c == " " || c == "\n" { text.removeLast() }
            if text.isEmpty { runs.removeLast(); continue }
            runs[runs.count - 1].text = text
            break
        }
        for k in runs.indices {
            runs[k].text = runs[k].text
                .replacingOccurrences(of: " \n", with: "\n")
                .replacingOccurrences(of: "\n ", with: "\n")
        }
        return runs
    }
}

struct BlockBuilder {
    let baseURL: URL?
    let maxBlocks: Int

    private(set) var blocks: [ContentBlock] = []
    private var runs: [InlineRun] = []

    // Inline style state.
    private var boldDepth = 0
    private var italicDepth = 0
    private var underlineDepth = 0
    private var codeDepth = 0
    private var linkStack: [URL?] = []

    // Block context.
    private var headingLevel: Int?
    private var preDepth = 0
    private var listStack: [Bool] = []           // ordered flags, innermost last
    private var listItems: [ListItem] = []       // items of the outermost open list
    private var listItemDepth = 0
    private var quoteDepth = 0
    private var quoteParagraphs: [InlineText] = []
    private var quoteAttribution: String?
    private var inAttribution = false
    private var figureDepth = 0
    private var figureImage: ArticleImage?
    private var inFigcaption = false
    private var captionText = ""
    private var creditDepth = 0
    private var creditText = ""
    private var dropDepth = 0
    private var droppedElementStack: [String] = []

    /// Elements whose content is discarded entirely.
    static let droppedElements: Set<String> = [
        "script", "style", "template", "svg", "math", "form", "button", "select", "option",
        "textarea", "input", "noscript", "head", "title", "canvas", "map", "dialog", "nav",
    ]
    /// Embeds: never loaded; replaced with a notice.
    static let embedElements: Set<String> = ["iframe", "video", "audio", "object", "embed"]
    static let voidElements: Set<String> = [
        "br", "hr", "img", "input", "meta", "link", "source", "track", "wbr", "area", "base", "col", "param", "embed",
    ]
    static let blockBoundaries: Set<String> = [
        "p", "div", "section", "article", "header", "main", "aside", "table", "tr", "td", "th",
        "thead", "tbody", "tfoot", "caption", "dl", "dt", "dd", "address", "details", "summary",
    ]

    init(baseURL: URL?, maxBlocks: Int) {
        self.baseURL = baseURL
        self.maxBlocks = maxBlocks
    }

    var isFull: Bool { blocks.count >= maxBlocks }

    mutating func consume(_ token: HTMLToken) {
        switch token {
        case let .start(name, attributes, selfClosing):
            if dropDepth > 0 {
                if !Self.voidElements.contains(name), !selfClosing,
                   Self.droppedElements.contains(name) || Self.embedElements.contains(name) {
                    droppedElementStack.append(name)
                    dropDepth += 1
                }
                return
            }
            start(name, attributes: attributes, selfClosing: selfClosing)
        case let .end(name):
            if dropDepth > 0 {
                if let last = droppedElementStack.last, last == name {
                    droppedElementStack.removeLast()
                    dropDepth -= 1
                }
                return
            }
            end(name)
        case let .text(string):
            guard dropDepth == 0 else { return }
            appendText(string)
        }
    }

    mutating func finish() -> [ContentBlock] {
        flushParagraph()
        while !listStack.isEmpty { end(listStack.last! ? "ol" : "ul") }
        if quoteDepth > 0 { quoteDepth = 1; end("blockquote") }
        if figureDepth > 0 { figureDepth = 1; end("figure") }
        return Array(blocks.prefix(maxBlocks))
    }

    // MARK: Start / end

    private mutating func start(_ name: String, attributes: [String: String], selfClosing: Bool) {
        if Self.embedElements.contains(name) {
            flushParagraph()
            let host = attributes["src"].flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL.host }
            append(.embedNotice(host: host))
            if !Self.voidElements.contains(name), !selfClosing {
                dropDepth += 1
                droppedElementStack.append(name)
            }
            return
        }
        if Self.droppedElements.contains(name) {
            if !Self.voidElements.contains(name), !selfClosing {
                dropDepth += 1
                droppedElementStack.append(name)
            }
            return
        }
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            flushParagraph()
            let rank = Int(String(name.dropFirst())) ?? 2
            headingLevel = min(max(rank, 2), 4)   // h1 in a body is treated as a section heading
        case "ul", "ol":
            if listStack.isEmpty {
                flushParagraph()
                listItems = []
            } else if listItemDepth > 0 {
                flushListItemText()
            }
            listStack.append(name == "ol")
        case "li":
            if listItemDepth > 0 { flushListItemText() }
            listItemDepth += 1
        case "blockquote":
            flushParagraph()
            quoteDepth += 1
        case "cite", "footer":
            if quoteDepth > 0 {
                flushParagraph()
                inAttribution = true
            } else if name == "footer" {
                flushParagraph()
            }
        case "figure":
            flushParagraph()
            figureDepth += 1
        case "figcaption":
            flushParagraph()
            inFigcaption = true
        case "img":
            guard let src = attributes["src"], let url = LinkPolicy.resolveImage(src, base: baseURL) else { return }
            let image = ArticleImage(
                url: url,
                width: attributes["width"].flatMap(Double.init),
                height: attributes["height"].flatMap(Double.init),
                alt: attributes["alt"].flatMap { $0.isEmpty ? nil : $0 },
                caption: nil,
                credit: nil)
            if figureDepth > 0, figureImage == nil {
                figureImage = image
            } else {
                flushParagraph()
                append(.image(image))
            }
        case "br":
            runs.append(styled("\n"))
        case "hr":
            flushParagraph()
            append(.divider)
        case "pre":
            flushParagraph()
            preDepth += 1
            codeDepth += 1
        case "a":
            linkStack.append(attributes["href"].flatMap { LinkPolicy.resolveLink($0, base: baseURL) })
        case "strong", "b":
            boldDepth += 1
        case "em", "i":
            italicDepth += 1
        case "u":
            underlineDepth += 1
        case "code", "kbd", "samp":
            codeDepth += 1
        case "span", "small":
            if inFigcaption, let cls = attributes["class"]?.lowercased(),
               cls.contains("credit") || cls.contains("copyright") {
                creditDepth += 1
            }
        default:
            if Self.blockBoundaries.contains(name) { blockBoundary() }
        }
    }

    private mutating func end(_ name: String) {
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            flushParagraph()
            headingLevel = nil
        case "ul", "ol":
            guard !listStack.isEmpty else { return }
            if listItemDepth > 0 { flushListItemText() }
            listStack.removeLast()
            if listStack.isEmpty {
                listItemDepth = 0
                if !listItems.isEmpty { append(.list(ordered: name == "ol", items: listItems)) }
                listItems = []
            }
        case "li":
            guard listItemDepth > 0 else { return }
            flushListItemText()
            listItemDepth -= 1
        case "blockquote":
            guard quoteDepth > 0 else { return }
            flushParagraph()
            quoteDepth -= 1
            if quoteDepth == 0 {
                if !quoteParagraphs.isEmpty || quoteAttribution != nil {
                    append(.quote(paragraphs: quoteParagraphs, attribution: quoteAttribution))
                }
                quoteParagraphs = []
                quoteAttribution = nil
            }
        case "cite", "footer":
            if inAttribution {
                let text = InlineText(InlineTextNormaliser.trim(runs)).plainText
                runs = []
                if !text.isEmpty {
                    let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "—–- ").union(.whitespaces))
                    quoteAttribution = quoteAttribution.map { $0 + " " + cleaned } ?? cleaned
                }
                inAttribution = false
            } else if name == "footer" {
                flushParagraph()
            }
        case "figcaption":
            flushParagraph()
            inFigcaption = false
        case "figure":
            guard figureDepth > 0 else { return }
            flushParagraph()
            figureDepth -= 1
            if figureDepth == 0 {
                if let image = figureImage {
                    let caption = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let credit = creditText.trimmingCharacters(in: .whitespacesAndNewlines)
                    append(.image(ArticleImage(
                        url: image.url, width: image.width, height: image.height, alt: image.alt,
                        caption: caption.isEmpty ? nil : caption,
                        credit: credit.isEmpty ? nil : credit)))
                } else if !captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    append(.paragraph(InlineText(plain: captionText.trimmingCharacters(in: .whitespacesAndNewlines))))
                }
                figureImage = nil
                captionText = ""
                creditText = ""
            }
        case "pre":
            guard preDepth > 0 else { return }
            flushParagraph()
            preDepth -= 1
            codeDepth = max(0, codeDepth - 1)
        case "a":
            if !linkStack.isEmpty { linkStack.removeLast() }
        case "strong", "b":
            boldDepth = max(0, boldDepth - 1)
        case "em", "i":
            italicDepth = max(0, italicDepth - 1)
        case "u":
            underlineDepth = max(0, underlineDepth - 1)
        case "code", "kbd", "samp":
            codeDepth = max(0, codeDepth - 1)
        case "span", "small":
            if creditDepth > 0, inFigcaption {
                creditDepth -= 1
            }
        default:
            if Self.blockBoundaries.contains(name) { blockBoundary() }
        }
    }

    // MARK: Text

    private func styled(_ text: String) -> InlineRun {
        InlineRun(text, bold: boldDepth > 0, italic: italicDepth > 0, code: codeDepth > 0,
                  link: linkStack.last(where: { $0 != nil }) ?? nil, underline: underlineDepth > 0)
    }

    private mutating func appendText(_ raw: String) {
        if creditDepth > 0, inFigcaption {
            creditText += collapse(raw, after: creditText.last)
            return
        }
        guard preDepth == 0 else {
            runs.append(styled(raw))
            return
        }
        let previousCharacter = runs.last?.text.last
        let text = collapse(raw, after: previousCharacter)
        guard !text.isEmpty else { return }
        runs.append(styled(text))
    }

    /// Collapses HTML whitespace to single spaces, avoiding a double space across runs.
    private func collapse(_ raw: String, after previous: Character?) -> String {
        var out = ""
        var lastWasSpace = previous == nil || previous == " " || previous == "\n"
        for ch in raw {
            if ch == " " || ch == "\n" || ch == "\t" || ch == "\r" || ch == "\u{0C}" {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out
    }

    // MARK: Flushing

    /// A generic block boundary (p, div, td...). Inside a list item, paragraphs
    /// are kept within the item and separated by a line break instead.
    private mutating func blockBoundary() {
        if listItemDepth > 0 {
            if let last = runs.last?.text.last, last != "\n" { runs.append(InlineRun("\n")) }
        } else {
            flushParagraph()
        }
    }

    private mutating func flushListItemText() {
        let text = InlineText(InlineTextNormaliser.trim(runs))
        runs = []
        guard !text.isBlank else { return }
        listItems.append(ListItem(text: text, level: max(0, listStack.count - 1)))
    }

    private mutating func flushParagraph() {
        if listItemDepth > 0, !listStack.isEmpty {
            // Leaving list context abruptly (e.g. a heading inside an <li>): keep text in the item.
            flushListItemText()
            return
        }
        let text = InlineText(InlineTextNormaliser.trim(runs, preformatted: preDepth > 0))
        runs = []
        guard !text.isBlank else { return }
        if inFigcaption {
            captionText += (captionText.isEmpty ? "" : " ") + text.plainText
        } else if let level = headingLevel {
            append(.heading(level: level, text: text))
        } else if quoteDepth > 0 {
            quoteParagraphs.append(text)
        } else {
            append(.paragraph(text))
        }
    }

    private mutating func append(_ block: ContentBlock) {
        guard blocks.count < maxBlocks else { return }
        if case .divider = block, case .divider? = blocks.last { return }
        blocks.append(block)
    }
}
