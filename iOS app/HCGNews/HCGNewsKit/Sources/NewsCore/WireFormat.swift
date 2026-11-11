import Foundation
import HCGTransport

// Decoding of the PROPOSED HCG News Content API v1 responses
// (docs/HCG-NEWS-CONTENT-API-PROPOSAL.md). Not a confirmed contract.

/// `GET meta`
public struct MetaResponse: Decodable, Sendable {
    public struct Capabilities: Decodable, Sendable {
        public let search: Bool?
        /// Filters the server search endpoint accepts, e.g. ["section", "type"].
        public let searchFilters: [String]?
        /// True when article detail returns the full body (offline download allowed).
        public let fullContent: Bool?
    }
    public let contractVersion: String
    public let capabilities: Capabilities?
}

/// `GET sections`
struct SectionsResponse: Decodable {
    let sections: [NewsSection]
}

/// Paged list response (`GET articles`, `GET search`).
struct PageResponse: Decodable {
    let items: [ArticleSummary]
    let nextCursor: String?

    var page: ArticlePage { ArticlePage(items: items, nextCursor: nextCursor) }
}

/// `GET home`
struct HomeResponse: Decodable {
    let featured: [ArticleSummary]?
    let breaking: [ArticleSummary]?
    let latest: PageResponse
}

/// `GET articles/{id}`
struct ArticleResponse: Decodable {
    let summary: ArticleSummary
    let body: Body?
    let sources: [ArticleSource]
    let corrections: [ArticleCorrection]
    let sponsor: SponsorNotice?
    let audio: ArticleAudio?
    let related: [ArticleSummary]

    struct Body: Decodable {
        let format: String
        let blocks: [WireBlock]?
        let html: String?
    }

    enum CodingKeys: String, CodingKey { case body, sources, corrections, sponsor, audio, related }

    init(from decoder: Decoder) throws {
        summary = try ArticleSummary(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        body = try c.decodeIfPresent(Body.self, forKey: .body)
        sources = (try? c.decodeIfPresent([ArticleSource].self, forKey: .sources)) ?? []
        // Optional editorial metadata: malformed entries are dropped, never invented.
        corrections = ((try? c.decodeIfPresent([ArticleCorrection].self, forKey: .corrections)) ?? [])
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { ($0.issuedAt ?? .distantPast) > ($1.issuedAt ?? .distantPast) }
        sponsor = try? c.decodeIfPresent(SponsorNotice.self, forKey: .sponsor)
        if let audio = try? c.decodeIfPresent(ArticleAudio.self, forKey: .audio), audio.url.scheme?.lowercased() == "https" {
            self.audio = audio
        } else {
            self.audio = nil
        }
        related = (try? c.decodeIfPresent([ArticleSummary].self, forKey: .related)) ?? []
    }

    func article(baseURL: URL?, now: Date = Date()) -> Article {
        let parser = HTMLContentParser(baseURL: baseURL ?? summary.canonicalURL)
        var blocks: [ContentBlock] = []
        var completeness = ContentCompleteness.full
        if let body {
            switch body.format.lowercased() {
            case "blocks":
                // Unknown block types become an explicit notice; blank blocks are dropped.
                blocks = (body.blocks ?? []).compactMap { $0.contentBlock(parser: parser) }
            case "html":
                blocks = parser.parse(body.html ?? "")
            case "summary":
                completeness = .summaryOnly
            default:
                // Unknown body format: kept as an explicit notice so the rest of the article still shows.
                blocks = [.unsupported(type: body.format)]
            }
        } else {
            completeness = .summaryOnly
        }
        return Article(summary: summary, blocks: blocks, sources: sources, corrections: corrections,
                       sponsor: sponsor, audio: audio,
                       related: PublicationVisibility.filter(related, now: now).filter { $0.id != summary.id },
                       completeness: completeness)
    }
}

/// A structured content block on the wire. Unknown types decode to `nil` content.
struct WireBlock: Decodable {
    let type: String
    let level: Int?
    let text: String?
    let html: String?
    let ordered: Bool?
    let items: [String]?
    let attribution: String?
    let image: ArticleImage?
    let url: String?

    enum CodingKeys: String, CodingKey { case type, level, text, html, ordered, items, attribution, image, url }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        level = try c.decodeIfPresent(Int.self, forKey: .level)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        html = try c.decodeIfPresent(String.self, forKey: .html)
        ordered = try c.decodeIfPresent(Bool.self, forKey: .ordered)
        items = try? c.decodeIfPresent([String].self, forKey: .items)
        attribution = try c.decodeIfPresent(String.self, forKey: .attribution)
        image = try? c.decodeIfPresent(ArticleImage.self, forKey: .image)
        url = try c.decodeIfPresent(String.self, forKey: .url)
    }

    /// Inline content: `html` is sanitised; `text` is taken literally (never parsed as HTML).
    private func inline(_ parser: HTMLContentParser) -> InlineText {
        if let html { return parser.parseInline(html) }
        return InlineText(plain: (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func contentBlock(parser: HTMLContentParser) -> ContentBlock? {
        switch type.lowercased() {
        case "heading":
            let t = inline(parser)
            return t.isBlank ? nil : .heading(level: min(max(level ?? 2, 2), 4), text: t)
        case "paragraph":
            let t = inline(parser)
            return t.isBlank ? nil : .paragraph(t)
        case "list":
            let listItems = (items ?? []).map { parser.parseInline($0) }.filter { !$0.isBlank }
            return listItems.isEmpty ? nil : .list(ordered: ordered ?? false, items: listItems.map { ListItem(text: $0) })
        case "quote":
            let t = inline(parser)
            guard !t.isBlank else { return nil }
            return .quote(paragraphs: [t], attribution: attribution?.trimmingCharacters(in: .whitespacesAndNewlines))
        case "image":
            guard let image, image.url.scheme?.lowercased() == "https" else { return nil }
            return .image(image)
        case "divider":
            return .divider
        case "embed":
            return .embedNotice(host: url.flatMap { URL(string: $0)?.host })
        default:
            return .unsupported(type: type)
        }
    }
}

/// Error body the proposed API returns on non-2xx responses.
struct APIErrorBody: Decodable {
    let error: String?
    let message: String?
}
