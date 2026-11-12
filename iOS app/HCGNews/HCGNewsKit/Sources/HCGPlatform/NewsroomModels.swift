import Foundation
import NewsCore

/// A row in the newsroom's article list.
public struct NewsroomArticleSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let slug: String?
    public let status: String
    public let contentType: String?
    public let publishedAt: Date?
    public let updatedAt: Date?
    public let isFeatured: Bool
    public let isBreaking: Bool
    public let isDemo: Bool
    public let sectionName: String?
    public let authorName: String?
    public let createdBy: String?

    public var editorialStatus: EditorialStatus? { EditorialStatus(rawValue: status) }

    /// Published with a publication time still in the future.
    public func isScheduled(now: Date = Date()) -> Bool {
        status == EditorialStatus.published.rawValue && (publishedAt.map { $0 > now } ?? false)
    }

    /// Live on the publication right now.
    public func isLive(now: Date = Date()) -> Bool {
        status == EditorialStatus.published.rawValue && (publishedAt.map { $0 <= now } ?? false)
    }
}

/// The editable fields of an article. Only fields that changed are ever sent.
public struct NewsroomArticleFields: Equatable, Sendable, Codable {
    public var title: String
    public var subtitle: String
    public var slug: String
    public var excerpt: String
    public var body: String
    public var contentType: String
    public var categoryID: String?
    public var authorID: String?
    public var featuredImageURL: String
    public var featuredImageAlt: String
    public var featuredImageCaption: String
    public var featuredImageCredit: String
    public var isFeatured: Bool
    public var isBreaking: Bool
    public var seoTitle: String
    public var seoDescription: String
    public var tags: [String]
    public var sources: String
    public var correctionNotes: String

    public init(title: String = "", subtitle: String = "", slug: String = "", excerpt: String = "", body: String = "",
                contentType: String = "news", categoryID: String? = nil, authorID: String? = nil,
                featuredImageURL: String = "", featuredImageAlt: String = "", featuredImageCaption: String = "",
                featuredImageCredit: String = "", isFeatured: Bool = false, isBreaking: Bool = false,
                seoTitle: String = "", seoDescription: String = "", tags: [String] = [], sources: String = "",
                correctionNotes: String = "") {
        self.title = title; self.subtitle = subtitle; self.slug = slug; self.excerpt = excerpt; self.body = body
        self.contentType = contentType; self.categoryID = categoryID; self.authorID = authorID
        self.featuredImageURL = featuredImageURL; self.featuredImageAlt = featuredImageAlt
        self.featuredImageCaption = featuredImageCaption; self.featuredImageCredit = featuredImageCredit
        self.isFeatured = isFeatured; self.isBreaking = isBreaking; self.seoTitle = seoTitle
        self.seoDescription = seoDescription; self.tags = tags; self.sources = sources; self.correctionNotes = correctionNotes
    }

    /// Column values that differ from `base`, ready for a PATCH. Empty text becomes null,
    /// as on the website.
    public func changes(from base: NewsroomArticleFields) -> [String: Any] {
        var out: [String: Any] = [:]
        func text(_ key: String, _ new: String, _ old: String, nullable: Bool = true) {
            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            // Whitespace-only differences in plain fields aren't changes; the body is compared exactly.
            if key == "body" ? new == old : trimmed == old.trimmingCharacters(in: .whitespacesAndNewlines) { return }
            out[key] = (nullable && trimmed.isEmpty) ? NSNull() : (key == "body" ? new : trimmed)
        }
        text("title", title, base.title, nullable: false)
        text("subtitle", subtitle, base.subtitle)
        text("slug", slug, base.slug, nullable: false)
        text("excerpt", excerpt, base.excerpt)
        text("body", body, base.body, nullable: false)
        text("content_type", contentType, base.contentType, nullable: false)
        if categoryID != base.categoryID { out["category_id"] = categoryID ?? NSNull() }
        if authorID != base.authorID { out["author_id"] = authorID ?? NSNull() }
        text("featured_image_url", featuredImageURL, base.featuredImageURL)
        text("featured_image_alt", featuredImageAlt, base.featuredImageAlt)
        text("featured_image_caption", featuredImageCaption, base.featuredImageCaption)
        text("featured_image_credit", featuredImageCredit, base.featuredImageCredit)
        if isFeatured != base.isFeatured { out["is_featured"] = isFeatured }
        if isBreaking != base.isBreaking { out["is_breaking"] = isBreaking }
        text("seo_title", seoTitle, base.seoTitle)
        text("seo_description", seoDescription, base.seoDescription)
        if tags != base.tags { out["tags"] = tags }
        text("sources", sources, base.sources)
        text("correction_notes", correctionNotes, base.correctionNotes)
        return out
    }

    /// The website's slug rule (lowercase ASCII, hyphens, at most 90 characters).
    public static func slugify(_ text: String) -> String {
        // Same steps as the website: lowercase, NFKD, drop combining marks, runs of anything
        // else become one hyphen, trim hyphens, keep 90 characters.
        let decomposed = text.lowercased().decomposedStringWithCompatibilityMapping.unicodeScalars
            .filter { !(0x300...0x36F).contains($0.value) }
        var out = ""
        var pendingHyphen = false
        for scalar in decomposed {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                if pendingHyphen, !out.isEmpty { out.append("-") }
                pendingHyphen = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingHyphen = true
            }
        }
        return String(out.prefix(90))
    }

    /// Problems that block publication, using the website's rules.
    public var publicationProblems: [String] {
        var problems: [String] = []
        if categoryID == nil { problems.append("Choose a section before publishing.") }
        let bodyText = body.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if title.trimmingCharacters(in: .whitespaces).isEmpty || bodyText.isEmpty || slug.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("Complete the headline, article body and slug before publishing.")
        }
        return problems
    }
}

/// A full newsroom article as the server returned it.
public struct NewsroomArticle: Identifiable, Equatable, Sendable {
    public let id: String
    public let createdBy: String?
    public let createdAt: Date?
    /// The server's `updated_at`, exactly as sent. Used to detect concurrent edits.
    public let revision: String
    public let updatedAt: Date?
    public let status: String
    public let publishedAt: Date?
    public let isDemo: Bool
    public let viewCount: Int?
    public let fields: NewsroomArticleFields

    public var editorialStatus: EditorialStatus? { EditorialStatus(rawValue: status) }

    public func isScheduled(now: Date = Date()) -> Bool {
        status == EditorialStatus.published.rawValue && (publishedAt.map { $0 > now } ?? false)
    }

    public func isLive(now: Date = Date()) -> Bool {
        status == EditorialStatus.published.rawValue && (publishedAt.map { $0 <= now } ?? false)
    }
}

public struct NewsroomVersion: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String?
    public let subtitle: String?
    public let body: String?
    public let status: String?
    public let createdAt: Date?
    public let createdBy: String?
}

public struct NewsroomAuditEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let createdAt: Date?
    public let actorID: String?
    public let action: String
    public let entity: String?
    public let summary: String?
}

public struct NewsroomCategory: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let slug: String
    public let description: String?
    public let sortOrder: Int?
    public let isVisible: Bool
}

public struct NewsroomAuthor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let slug: String?
    public let title: String?
    public let userID: String?
}

public struct NewsroomMedia: Identifiable, Equatable, Sendable {
    public let id: String
    public let url: URL?
    public let storagePath: String
    public let kind: String
    public let mimeType: String?
    public let sizeBytes: Int?
    public let uploadedBy: String?
    public let caption: String?
    public let altText: String?
    public let credit: String?
    public let createdAt: Date?
}

/// Errors from saving, with the server's current version when someone else changed it.
public enum NewsroomSaveError: Error, Equatable, Sendable {
    case conflict(server: NewsroomArticle)
    case platform(PlatformError)

    public var message: String {
        switch self {
        case .conflict: "This article was changed by someone else since you opened it. Nothing was overwritten."
        case .platform(let error): error.message
        }
    }
}
