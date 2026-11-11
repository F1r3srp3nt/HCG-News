import Foundation
import NewsCore

// Local newsroom drafts.
//
// A draft is the author's own work stored on this device. Saving a draft is
// never submission or publication: it is labelled "Local draft" everywhere.
// A draft may later be linked to a server draft by an explicit user action,
// when a newsroom API exists and HCG authorises it.

public enum DraftBlockKind: String, Codable, Sendable, CaseIterable {
    case paragraph, heading, bulletList, numberedList, quote, image

    public var title: String {
        switch self {
        case .paragraph: "Paragraph"
        case .heading: "Subheading"
        case .bulletList: "Bulleted list"
        case .numberedList: "Numbered list"
        case .quote: "Quotation"
        case .image: "Image"
        }
    }
}

/// One block of a draft body. List items are separate lines of `text`.
public struct DraftBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: DraftBlockKind
    /// Paragraph/heading/quote text, or one list item per line. Supports
    /// **bold**, *italic* and [link](https://…) markup.
    public var text: String
    /// Quotation attribution.
    public var attribution: String
    /// Image block: the attachment and its metadata.
    public var image: DraftImageMeta?

    public init(id: UUID = UUID(), kind: DraftBlockKind, text: String = "", attribution: String = "", image: DraftImageMeta? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.attribution = attribution
        self.image = image
    }
}

/// Image metadata kept with the draft. Alt text is required before submission.
public struct DraftImageMeta: Codable, Equatable, Sendable {
    public var attachmentID: UUID?
    public var caption: String
    public var credit: String
    public var altText: String

    public init(attachmentID: UUID? = nil, caption: String = "", credit: String = "", altText: String = "") {
        self.attachmentID = attachmentID
        self.caption = caption
        self.credit = credit
        self.altText = altText
    }
}

/// Upload state of a local media file. Separate from the draft's own state.
public enum UploadState: Codable, Equatable, Sendable {
    /// Stored on this device only.
    case localOnly
    case uploading
    /// Accepted by the newsroom service under this remote id.
    case uploaded(remoteID: String)
    case failed(reason: String)
}

public struct MediaAttachment: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var filename: String
    public var mimeType: String
    public var byteCount: Int
    public var addedAt: Date
    public var uploadState: UploadState

    public init(id: UUID = UUID(), filename: String, mimeType: String, byteCount: Int, addedAt: Date, uploadState: UploadState = .localOnly) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.addedAt = addedAt
        self.uploadState = uploadState
    }
}

/// Link to a server-side draft, set only after an explicit, successful server call.
public struct ServerLink: Codable, Equatable, Sendable {
    public var serverDraftID: String
    /// Server revision this local draft was last synchronised with.
    public var serverRevision: String
    /// Server status as returned (e.g. draft, in_review, approved, published, archived).
    public var remoteStatus: String
    public var lastSyncedAt: Date
    public var environment: String

    public init(serverDraftID: String, serverRevision: String, remoteStatus: String, lastSyncedAt: Date, environment: String) {
        self.serverDraftID = serverDraftID
        self.serverRevision = serverRevision
        self.remoteStatus = remoteStatus
        self.lastSyncedAt = lastSyncedAt
        self.environment = environment
    }
}

/// An author the publication has verified (from the newsroom service). The app
/// never creates authors or bylines from free text.
public struct VerifiedAuthor: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let title: String?

    public init(id: String, name: String, title: String? = nil) {
        self.id = id
        self.name = name
        self.title = title
    }
}

public struct Draft: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public var headline: String
    public var standfirst: String
    public var blocks: [DraftBlock]
    public var sectionSlug: String?
    public var sectionName: String?
    /// Editorial type wire value (news, analysis, opinion, sponsored, announcement).
    public var editorialTypeWire: String?
    /// Verified authors chosen from the newsroom service's list.
    public var authors: [VerifiedAuthor]
    public var cover: DraftImageMeta?
    public var attachments: [MediaAttachment]
    /// Set only by an explicit successful server call. Nil = local draft only.
    public var serverLink: ServerLink?
    /// Increments on every local save.
    public var localRevision: Int
    /// Note shown when a server link was removed (e.g. identity configuration changed).
    public var detachedNote: String?

    public init(id: UUID = UUID(), now: Date) {
        self.id = id
        self.createdAt = now
        self.updatedAt = now
        self.headline = ""
        self.standfirst = ""
        self.blocks = [DraftBlock(kind: .paragraph)]
        self.authors = []
        self.attachments = []
        self.localRevision = 0
    }

    public var editorialType: EditorialType? { editorialTypeWire.map(EditorialType.init(rawValue:)) }

    /// True when there are local edits not yet sent to the server (or never linked).
    public var hasUnsyncedChanges: Bool {
        guard let link = serverLink else { return true }
        return updatedAt > link.lastSyncedAt
    }

    /// Always starts with "Local draft": saving locally is never submission or publication.
    public var stateLabel: String {
        guard let link = serverLink else { return "Local draft" }
        let status = link.remoteStatus.replacingOccurrences(of: "_", with: " ")
        return hasUnsyncedChanges
            ? "Local draft · changes not sent · newsroom status: \(status)"
            : "Local draft · matches newsroom draft · status: \(status)"
    }

    public var displayTitle: String {
        let trimmed = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled draft" : trimmed
    }

    public var wordCount: Int {
        ([headline, standfirst] + blocks.map(\.text)).joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Problems that block submission to a newsroom (local saving is always allowed).
    public var submissionProblems: [String] {
        var problems: [String] = []
        if headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append("Add a headline.") }
        if sectionSlug == nil { problems.append("Choose a section.") }
        if editorialTypeWire == nil { problems.append("Choose an editorial type.") }
        if !blocks.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            problems.append("Write the article body.")
        }
        let images = blocks.compactMap(\.image) + (cover.map { [$0] } ?? [])
        if images.contains(where: { $0.attachmentID != nil && $0.altText.trimmingCharacters(in: .whitespaces).isEmpty }) {
            problems.append("Add alt text to every image.")
        }
        return problems
    }
}

// MARK: - Search and filtering

public struct DraftFilter: Equatable, Sendable {
    public enum Link: String, CaseIterable, Sendable { case all, localOnly, linked, unsynced }
    public var query: String
    public var editorialTypeWire: String?
    public var sectionSlug: String?
    public var link: Link

    public init(query: String = "", editorialTypeWire: String? = nil, sectionSlug: String? = nil, link: Link = .all) {
        self.query = query
        self.editorialTypeWire = editorialTypeWire
        self.sectionSlug = sectionSlug
        self.link = link
    }

    public func matches(_ draft: Draft) -> Bool {
        if let type = editorialTypeWire, draft.editorialTypeWire != type { return false }
        if let slug = sectionSlug, draft.sectionSlug != slug { return false }
        switch link {
        case .all: break
        case .localOnly: if draft.serverLink != nil { return false }
        case .linked: if draft.serverLink == nil { return false }
        case .unsynced: if draft.serverLink == nil || !draft.hasUnsyncedChanges { return false }
        }
        let terms = LocalArticleSearch.normalise(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return true }
        let haystack = LocalArticleSearch.normalise(([draft.headline, draft.standfirst] + draft.blocks.map(\.text)).joined(separator: " "))
        return terms.allSatisfy { haystack.contains($0) }
    }
}

// MARK: - Markup and preview

public enum DraftMarkup {
    /// Parses **bold**, *italic* and [text](https://url) into inline runs.
    /// Links must pass the same policy as published articles.
    public static func inline(_ text: String) -> InlineText {
        var runs: [InlineRun] = []
        var bold = false, italic = false
        var buffer = ""
        let chars = Array(text)
        var i = 0
        func flush() {
            if !buffer.isEmpty { runs.append(InlineRun(buffer, bold: bold, italic: italic)); buffer = "" }
        }
        while i < chars.count {
            let c = chars[i]
            if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                flush(); bold.toggle(); i += 2; continue
            }
            if c == "*" {
                flush(); italic.toggle(); i += 1; continue
            }
            if c == "[", let close = chars[(i + 1)...].firstIndex(of: "]"),
               close + 1 < chars.count, chars[close + 1] == "(",
               let end = matchingParen(chars, from: close + 1) {
                let label = String(chars[(i + 1)..<close])
                let target = String(chars[(close + 2)..<end])
                flush()
                let url = URL(string: target).flatMap(LinkPolicy.allowedExternalURL)
                runs.append(InlineRun(label, bold: bold, italic: italic, link: url))
                i = end + 1
                continue
            }
            buffer.append(c)
            i += 1
        }
        flush()
        return InlineText(runs)
    }

    /// Index of the ")" closing the "(" at `open`, honouring nested parentheses.
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

    /// Converts a draft into the reader's article model for a native preview.
    /// Image URLs point at local files supplied by `localImageURL`.
    public static func previewArticle(_ draft: Draft, localImageURL: (UUID) -> URL?) -> Article {
        func image(_ meta: DraftImageMeta?) -> ArticleImage? {
            guard let meta, let id = meta.attachmentID, let url = localImageURL(id) else { return nil }
            return ArticleImage(url: url, alt: meta.altText.isEmpty ? nil : meta.altText,
                                caption: meta.caption.isEmpty ? nil : meta.caption,
                                credit: meta.credit.isEmpty ? nil : meta.credit)
        }
        var blocks: [ContentBlock] = []
        for block in draft.blocks {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch block.kind {
            case .paragraph:
                if !text.isEmpty { blocks.append(.paragraph(inline(text))) }
            case .heading:
                if !text.isEmpty { blocks.append(.heading(level: 2, text: inline(text))) }
            case .bulletList, .numberedList:
                let items = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !items.isEmpty {
                    blocks.append(.list(ordered: block.kind == .numberedList, items: items.map { ListItem(text: inline($0)) }))
                }
            case .quote:
                if !text.isEmpty {
                    let attribution = block.attribution.trimmingCharacters(in: .whitespaces)
                    blocks.append(.quote(paragraphs: [inline(text)], attribution: attribution.isEmpty ? nil : attribution))
                }
            case .image:
                if let img = image(block.image) { blocks.append(.image(img)) }
            }
        }
        let summary = ArticleSummary(
            id: ArticleID("local-draft-\(draft.id.uuidString)"),
            headline: draft.displayTitle,
            standfirst: draft.standfirst.isEmpty ? nil : draft.standfirst,
            section: draft.sectionSlug.map { SectionRef(id: $0, slug: $0, name: draft.sectionName ?? $0) },
            editorialType: draft.editorialType,
            authors: draft.authors.map { Author(id: $0.id, name: $0.name, title: $0.title) },
            publishedAt: nil,
            image: image(draft.cover),
            status: nil)
        return Article(summary: summary, blocks: blocks)
    }
}
