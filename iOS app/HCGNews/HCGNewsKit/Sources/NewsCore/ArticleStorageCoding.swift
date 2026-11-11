import Foundation

// Stable, versioned on-device encoding of articles and content blocks.
// Used for offline copies and newsroom previews. This is the app's own
// storage format, not the wire format; it is decoded only from files the
// app wrote itself.

extension ContentBlock: Codable {
    private enum Kind: String, Codable {
        case heading, paragraph, list, quote, image, divider, embedNotice, unsupported
    }

    private enum CodingKeys: String, CodingKey {
        case kind, level, text, ordered, items, paragraphs, attribution, image, host, type
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .heading:
            self = .heading(level: try c.decode(Int.self, forKey: .level), text: try c.decode(InlineText.self, forKey: .text))
        case .paragraph:
            self = .paragraph(try c.decode(InlineText.self, forKey: .text))
        case .list:
            self = .list(ordered: try c.decode(Bool.self, forKey: .ordered), items: try c.decode([ListItem].self, forKey: .items))
        case .quote:
            self = .quote(paragraphs: try c.decode([InlineText].self, forKey: .paragraphs),
                          attribution: try c.decodeIfPresent(String.self, forKey: .attribution))
        case .image:
            self = .image(try c.decode(ArticleImage.self, forKey: .image))
        case .divider:
            self = .divider
        case .embedNotice:
            self = .embedNotice(host: try c.decodeIfPresent(String.self, forKey: .host))
        case .unsupported:
            self = .unsupported(type: try c.decode(String.self, forKey: .type))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heading(let level, let text):
            try c.encode(Kind.heading, forKey: .kind)
            try c.encode(level, forKey: .level)
            try c.encode(text, forKey: .text)
        case .paragraph(let text):
            try c.encode(Kind.paragraph, forKey: .kind)
            try c.encode(text, forKey: .text)
        case .list(let ordered, let items):
            try c.encode(Kind.list, forKey: .kind)
            try c.encode(ordered, forKey: .ordered)
            try c.encode(items, forKey: .items)
        case .quote(let paragraphs, let attribution):
            try c.encode(Kind.quote, forKey: .kind)
            try c.encode(paragraphs, forKey: .paragraphs)
            try c.encodeIfPresent(attribution, forKey: .attribution)
        case .image(let image):
            try c.encode(Kind.image, forKey: .kind)
            try c.encode(image, forKey: .image)
        case .divider:
            try c.encode(Kind.divider, forKey: .kind)
        case .embedNotice(let host):
            try c.encode(Kind.embedNotice, forKey: .kind)
            try c.encodeIfPresent(host, forKey: .host)
        case .unsupported(let type):
            try c.encode(Kind.unsupported, forKey: .kind)
            try c.encode(type, forKey: .type)
        }
    }
}

extension Article: Codable {
    private enum CodingKeys: String, CodingKey {
        case summary, blocks, sources, corrections, sponsor, audio, related, completeness
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            summary: try c.decode(ArticleSummary.self, forKey: .summary),
            blocks: try c.decode([ContentBlock].self, forKey: .blocks),
            sources: try c.decodeIfPresent([ArticleSource].self, forKey: .sources) ?? [],
            corrections: try c.decodeIfPresent([ArticleCorrection].self, forKey: .corrections) ?? [],
            sponsor: try c.decodeIfPresent(SponsorNotice.self, forKey: .sponsor),
            audio: try c.decodeIfPresent(ArticleAudio.self, forKey: .audio),
            related: try c.decodeIfPresent([ArticleSummary].self, forKey: .related) ?? [],
            completeness: try c.decodeIfPresent(ContentCompleteness.self, forKey: .completeness) ?? .full)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(summary, forKey: .summary)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(sources, forKey: .sources)
        try c.encode(corrections, forKey: .corrections)
        try c.encodeIfPresent(sponsor, forKey: .sponsor)
        try c.encodeIfPresent(audio, forKey: .audio)
        try c.encode(related, forKey: .related)
        try c.encode(completeness, forKey: .completeness)
    }
}
