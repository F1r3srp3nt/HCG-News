import Foundation
import HCGTransport

// Models for the HCG News reader.
//
// IMPORTANT: the wire format these decode is the PROPOSED "HCG News Content API v1"
// (docs/HCG-NEWS-CONTENT-API-PROPOSAL.md). No supported HCG News content API was
// available to inspect when this was written. Field names must be confirmed or
// changed by the owner of news.hakmicapitalgroup.com before any live use.
// Decoding is deliberately tolerant of absent optional fields and unknown enum values.

/// Stable backend identifier of an article. Bookmarks and navigation key on this,
/// never on the slug or headline (both can change after publication).
public struct ArticleID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            rawValue = string
        } else {
            // Numeric primary keys are accepted and kept as their decimal string.
            rawValue = String(try container.decode(Int64.self))
        }
        guard !rawValue.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Empty article id")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// News / Analysis / Opinion distinction, preserved exactly as supplied.
/// The five known values and their labels match the publication's own code
/// (observed in news.hakmicapitalgroup.com's served bundle, 11 Nov 2026).
public enum EditorialType: Hashable, Codable, Sendable {
    case news
    case analysis
    case opinion
    /// Paid or partner content. Must always be visibly labelled.
    case sponsored
    /// HCG's own announcements.
    case announcement
    /// A type the backend supplied that this version does not know. Shown verbatim.
    case other(String)

    public init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespaces).lowercased() {
        case "news", "report", "reporting": self = .news
        case "analysis": self = .analysis
        case "opinion", "comment", "commentary", "op-ed", "oped": self = .opinion
        case "sponsored": self = .sponsored
        case "announcement": self = .announcement
        default: self = .other(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }

    public var wireValue: String {
        switch self {
        case .news: "news"
        case .analysis: "analysis"
        case .opinion: "opinion"
        case .sponsored: "sponsored"
        case .announcement: "announcement"
        case .other(let value): value
        }
    }

    /// Reader-facing label.
    public var label: String {
        switch self {
        case .news: "News"
        case .analysis: "Analysis"
        case .opinion: "Opinion"
        case .sponsored: "Sponsored"
        case .announcement: "HCG Announcement"
        case .other(let value): value.capitalized
        }
    }
}

public struct SectionRef: Hashable, Codable, Sendable {
    public let id: String
    public let slug: String
    public let name: String

    public init(id: String, slug: String, name: String) {
        self.id = id
        self.slug = slug
        self.name = name
    }
}

/// A publication section, loaded from the backend's category source of truth.
public struct NewsSection: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let slug: String
    public let name: String
    public let description: String?
    /// Parent section slug for hierarchical sections (e.g. "Norwegian Politics" under "Politics").
    public let parentSlug: String?
    public let position: Int?

    public init(id: String, slug: String, name: String, description: String? = nil,
                parentSlug: String? = nil, position: Int? = nil) {
        self.id = id
        self.slug = slug
        self.name = name
        self.description = description
        self.parentSlug = parentSlug
        self.position = position
    }

    public var ref: SectionRef { SectionRef(id: id, slug: slug, name: name) }
}

/// A disclosure attached to a verified author identity by the backend.
/// The app never composes disclosure text and never matches on display names.
public struct AuthorDisclosure: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    /// The verified author identity this disclosure belongs to.
    public let authorID: String
    /// The disclosure text exactly as maintained by the publication.
    public let text: String
    /// Optional category supplied by the backend (e.g. "political-affiliation").
    public let kind: String?

    public init(id: String, authorID: String, text: String, kind: String? = nil) {
        self.id = id
        self.authorID = authorID
        self.text = text
        self.kind = kind
    }
}

public struct Author: Hashable, Codable, Sendable, Identifiable {
    /// Verified author identity (backend id), not a display name.
    public let id: String
    public let name: String
    public let title: String?
    /// Disclosures that editorial policy requires wherever this author's work appears.
    public let disclosures: [AuthorDisclosure]

    public init(id: String, name: String, title: String? = nil, disclosures: [AuthorDisclosure] = []) {
        self.id = id
        self.name = name
        self.title = title
        self.disclosures = disclosures
    }

    enum CodingKeys: String, CodingKey { case id, name, title, disclosures }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        disclosures = (try c.decodeIfPresent([AuthorDisclosure].self, forKey: .disclosures)) ?? []
    }
}

public struct ArticleImage: Hashable, Codable, Sendable {
    public let url: URL
    /// Intrinsic pixel size, when supplied, so layout can reserve the true aspect
    /// ratio before the image loads. Never used to force a card height.
    public let width: Double?
    public let height: Double?
    public let alt: String?
    public let caption: String?
    public let credit: String?

    public init(url: URL, width: Double? = nil, height: Double? = nil, alt: String? = nil,
                caption: String? = nil, credit: String? = nil) {
        self.url = url
        self.width = width
        self.height = height
        self.alt = alt
        self.caption = caption
        self.credit = credit
    }

    /// Width / height when both are positive.
    public var aspectRatio: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return width / height
    }
}

/// Explicit editorial breaking-news marker from the backend.
public struct BreakingFlag: Hashable, Codable, Sendable {
    public let active: Bool
    /// Optional end time chosen by the editor; the app stops showing it afterwards.
    public let expiresAt: Date?
    /// Optional short label chosen by the editor (e.g. "Breaking", "Developing").
    public let label: String?

    public init(active: Bool, expiresAt: Date? = nil, label: String? = nil) {
        self.active = active
        self.expiresAt = expiresAt
        self.label = label
    }
}

/// Access level supplied by the backend. Unknown values are treated as not
/// public (fail closed) by `PublicationVisibility`.
public enum AccessLevel: Hashable, Codable, Sendable {
    case `public`
    case restricted
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "public": self = .public
        case "restricted", "members", "signed_in", "signed-in": self = .restricted
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .public: try container.encode("public")
        case .restricted: try container.encode("restricted")
        case .unknown(let value): try container.encode(value)
        }
    }
}

/// Fields shared by list items and full articles.
public struct ArticleSummary: Hashable, Codable, Sendable, Identifiable {
    public let id: ArticleID
    public let slug: String?
    public let canonicalURL: URL?
    public let headline: String
    public let standfirst: String?
    public let section: SectionRef?
    public let editorialType: EditorialType?
    public let authors: [Author]
    public let publishedAt: Date?
    public let updatedAt: Date?
    public let image: ArticleImage?
    public let isFeatured: Bool
    public let breaking: BreakingFlag?
    public let access: AccessLevel
    /// Publication status, when the backend includes it. Only "published" is shown.
    public let status: String?

    public init(id: ArticleID, slug: String? = nil, canonicalURL: URL? = nil, headline: String,
                standfirst: String? = nil, section: SectionRef? = nil, editorialType: EditorialType? = nil,
                authors: [Author] = [], publishedAt: Date?, updatedAt: Date? = nil,
                image: ArticleImage? = nil, isFeatured: Bool = false, breaking: BreakingFlag? = nil,
                access: AccessLevel = .public, status: String? = "published") {
        self.id = id
        self.slug = slug
        self.canonicalURL = canonicalURL
        self.headline = headline
        self.standfirst = standfirst
        self.section = section
        self.editorialType = editorialType
        self.authors = authors
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.image = image
        self.isFeatured = isFeatured
        self.breaking = breaking
        self.access = access
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, canonicalURL = "canonicalUrl", headline, standfirst, section, editorialType
        case authors, publishedAt, updatedAt, image, isFeatured, breaking, access, status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ArticleID.self, forKey: .id)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        canonicalURL = try? c.decodeIfPresent(URL.self, forKey: .canonicalURL)
        headline = try c.decode(String.self, forKey: .headline)
        standfirst = try c.decodeIfPresent(String.self, forKey: .standfirst)
        section = try? c.decodeIfPresent(SectionRef.self, forKey: .section)
        editorialType = try c.decodeIfPresent(EditorialType.self, forKey: .editorialType)
        authors = (try? c.decodeIfPresent([Author].self, forKey: .authors)) ?? []
        publishedAt = try c.decodeIfPresent(Date.self, forKey: .publishedAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        // A malformed image must not hide the article; it is simply omitted.
        image = try? c.decodeIfPresent(ArticleImage.self, forKey: .image)
        isFeatured = (try c.decodeIfPresent(Bool.self, forKey: .isFeatured)) ?? false
        breaking = try? c.decodeIfPresent(BreakingFlag.self, forKey: .breaking)
        // Absent access means the backend did not mark it restricted.
        access = (try c.decodeIfPresent(AccessLevel.self, forKey: .access)) ?? .public
        status = try c.decodeIfPresent(String.self, forKey: .status)
    }

    /// All disclosures for this article's verified authors, de-duplicated by id.
    public var disclosures: [AuthorDisclosure] {
        var seen = Set<String>()
        return authors.flatMap(\.disclosures).filter { seen.insert($0.id).inserted }
    }

    /// "By A and B".
    public var bylineNames: String? {
        let names = authors.map(\.name).filter { !$0.isEmpty }
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }

    /// The canonical URL, only when it is an HTTPS URL on an HCG host.
    /// Used for sharing; anything else is not shared.
    public var shareableURL: URL? {
        HCGHostPolicy.isTrustedHCGURL(canonicalURL) ? canonicalURL : nil
    }
}

/// An external source cited by the article.
public struct ArticleSource: Hashable, Codable, Sendable, Identifiable {
    public let title: String
    public let url: URL?
    public let publisher: String?

    public var id: String { (url?.absoluteString ?? "") + "|" + title }

    public init(title: String, url: URL?, publisher: String? = nil) {
        self.title = title
        self.url = url
        self.publisher = publisher
    }

    enum CodingKeys: String, CodingKey { case title, url, publisher }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        url = (try? c.decodeIfPresent(URL.self, forKey: .url)).flatMap { LinkPolicy.allowedExternalURL($0) }
        publisher = try c.decodeIfPresent(String.self, forKey: .publisher)
    }
}

/// A full article as returned by the detail endpoint.
public struct Article: Hashable, Sendable, Identifiable {
    public let summary: ArticleSummary
    public let blocks: [ContentBlock]
    public let sources: [ArticleSource]

    public var id: ArticleID { summary.id }

    public init(summary: ArticleSummary, blocks: [ContentBlock], sources: [ArticleSource] = []) {
        self.summary = summary
        self.blocks = blocks
        self.sources = sources
    }
}

/// A page of results with an opaque cursor.
public struct ArticlePage: Hashable, Sendable {
    public let items: [ArticleSummary]
    public let nextCursor: String?

    public init(items: [ArticleSummary], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// Content of the Home screen as decided by the backend.
public struct HomeFeed: Hashable, Sendable {
    /// Editorially featured articles (backend flag/curation). May be empty.
    public let featured: [ArticleSummary]
    /// Articles the backend explicitly marks as breaking.
    public let breaking: [ArticleSummary]
    /// Latest published articles.
    public let latest: ArticlePage

    public init(featured: [ArticleSummary], breaking: [ArticleSummary], latest: ArticlePage) {
        self.featured = featured
        self.breaking = breaking
        self.latest = latest
    }
}

/// What the configured backend supports.
public struct NewsCapabilities: Hashable, Sendable {
    /// True when the backend offers full-text search across the publication.
    public let serverSearch: Bool

    public init(serverSearch: Bool) { self.serverSearch = serverSearch }
}
