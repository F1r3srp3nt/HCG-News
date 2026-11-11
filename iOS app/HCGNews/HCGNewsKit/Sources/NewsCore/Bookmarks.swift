import Foundation
import HCGTransport

/// A locally saved article reference.
///
/// Keyed by the stable backend `ArticleID`. Holds what the Saved list needs to
/// display. The article body lives in `OfflineLibrary` only when the reader
/// downloads it; removing a download keeps the bookmark.
public struct Bookmark: Hashable, Sendable, Identifiable {
    public let articleID: ArticleID
    public var headline: String
    public var standfirst: String?
    public var sectionName: String?
    public var sectionSlug: String?
    /// Editorial type as its wire value (e.g. "announcement"), so labels stay current.
    public var editorialTypeWire: String?
    public var bylineNames: String?
    public var publishedAt: Date?
    public var canonicalURL: URL?
    public let savedAt: Date
    /// Content marker of the snapshot (revision / update time), if the backend gave one.
    public var contentMarker: String?
    /// Configuration environment the bookmark was saved from.
    public var environment: String?

    public var id: ArticleID { articleID }

    public var editorialType: EditorialType? { editorialTypeWire.map(EditorialType.init(rawValue:)) }
    public var editorialTypeLabel: String? { editorialType?.label }

    public init(article: ArticleSummary, savedAt: Date = Date(), environment: String? = nil) {
        articleID = article.id
        headline = article.headline
        standfirst = article.standfirst
        sectionName = article.section?.name
        sectionSlug = article.section?.slug
        editorialTypeWire = article.editorialType?.wireValue
        bylineNames = article.bylineNames
        publishedAt = article.publishedAt
        canonicalURL = article.shareableURL
        self.savedAt = savedAt
        contentMarker = article.contentVersionMarker
        self.environment = environment
    }

    init(articleID: ArticleID, headline: String, standfirst: String?, sectionName: String?, sectionSlug: String?,
         editorialTypeWire: String?, bylineNames: String?, publishedAt: Date?, canonicalURL: URL?, savedAt: Date,
         contentMarker: String?, environment: String?) {
        self.articleID = articleID
        self.headline = headline
        self.standfirst = standfirst
        self.sectionName = sectionName
        self.sectionSlug = sectionSlug
        self.editorialTypeWire = editorialTypeWire
        self.bylineNames = bylineNames
        self.publishedAt = publishedAt
        self.canonicalURL = canonicalURL
        self.savedAt = savedAt
        self.contentMarker = contentMarker
        self.environment = environment
    }

    /// A summary good enough to list and open the article (no body).
    public var summary: ArticleSummary {
        ArticleSummary(id: articleID, canonicalURL: canonicalURL, headline: headline, standfirst: standfirst,
                       section: sectionName.map { SectionRef(id: sectionSlug ?? $0, slug: sectionSlug ?? "", name: $0) },
                       editorialType: editorialType,
                       authors: [], publishedAt: publishedAt)
    }
}

extension Bookmark: Codable {
    enum CodingKeys: String, CodingKey {
        case articleID, headline, standfirst, sectionName, sectionSlug, editorialTypeWire, bylineNames
        case publishedAt, canonicalURL, savedAt, contentMarker, environment
    }
}

/// Bookmark file schema v1 (Milestone 1). Kept only for migration.
struct BookmarkV1: Codable {
    let articleID: ArticleID
    let headline: String
    let standfirst: String?
    let sectionName: String?
    /// v1 stored the display label ("News", "HCG Announcement"...).
    let editorialType: String?
    let bylineNames: String?
    let publishedAt: Date?
    let canonicalURL: URL?
    let savedAt: Date

    /// Maps a v1 display label back to the wire value.
    static func wireValue(forLabel label: String?) -> String? {
        guard let label, !label.isEmpty else { return nil }
        switch label {
        case "News": return "news"
        case "Analysis": return "analysis"
        case "Opinion": return "opinion"
        case "Sponsored": return "sponsored"
        case "HCG Announcement": return "announcement"
        default: return label.lowercased()
        }
    }

    var migrated: Bookmark {
        Bookmark(articleID: articleID, headline: headline, standfirst: standfirst, sectionName: sectionName,
                 sectionSlug: nil, editorialTypeWire: Self.wireValue(forLabel: editorialType),
                 bylineNames: bylineNames, publishedAt: publishedAt, canonicalURL: canonicalURL,
                 savedAt: savedAt, contentMarker: nil, environment: nil)
    }
}

public enum BookmarkStoreError: Error, Equatable, Sendable {
    case writeFailed(String)
    /// The file was written by a newer version of the app; it is left untouched.
    case newerFileVersion(Int)
}

/// Persistent local bookmarks (JSON file in Application Support).
///
/// - Schema v2. A v1 file is migrated on first load; the v1 file is kept as
///   `bookmarks.v1-backup.json`.
/// - A file from a newer app version is never overwritten (writes are refused).
/// - A corrupt file is preserved as `*.corrupt-<timestamp>.json`; the store starts empty.
/// - No cloud synchronisation: there is no verified central bookmark contract.
public actor BookmarkStore {
    struct FileHeader: Codable { var version: Int }
    struct FileContents: Codable {
        var version: Int
        var bookmarks: [Bookmark]
    }
    struct FileContentsV1: Codable {
        var version: Int
        var bookmarks: [BookmarkV1]
    }

    public static let currentVersion = 2

    private let fileURL: URL
    private var bookmarks: [Bookmark] = []
    private var loaded = false
    private var blockedByNewerVersion: Int?
    public private(set) var recoveredFromCorruption = false
    public private(set) var migratedFromVersion: Int?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default location: `Application Support/HCGNews/bookmarks.json`.
    public static func defaultFileURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("HCGNews", isDirectory: true)
            .appendingPathComponent("bookmarks.json", isDirectory: false)
    }

    /// All bookmarks, most recently saved first.
    public func all() -> [Bookmark] {
        loadIfNeeded()
        return bookmarks
    }

    public func contains(_ id: ArticleID) -> Bool {
        loadIfNeeded()
        return bookmarks.contains { $0.articleID == id }
    }

    /// Non-nil when the file belongs to a newer app version and is read-only here.
    public func newerFileVersion() -> Int? {
        loadIfNeeded()
        return blockedByNewerVersion
    }

    /// Saves (or refreshes the stored snapshot of) an article. Keeps the original save time.
    public func save(_ article: ArticleSummary, at date: Date = Date(), environment: String? = nil) throws {
        loadIfNeeded()
        if let index = bookmarks.firstIndex(where: { $0.articleID == article.id }) {
            let original = bookmarks[index].savedAt
            bookmarks[index] = Bookmark(article: article, savedAt: original, environment: environment ?? bookmarks[index].environment)
        } else {
            bookmarks.insert(Bookmark(article: article, savedAt: date, environment: environment), at: 0)
        }
        try persist()
    }

    public func remove(_ id: ArticleID) throws {
        loadIfNeeded()
        let before = bookmarks.count
        bookmarks.removeAll { $0.articleID == id }
        if bookmarks.count != before { try persist() }
    }

    /// Toggles and returns the new saved state.
    @discardableResult
    public func toggle(_ article: ArticleSummary, at date: Date = Date(), environment: String? = nil) throws -> Bool {
        if contains(article.id) {
            try remove(article.id)
            return false
        }
        try save(article, at: date, environment: environment)
        return true
    }

    // MARK: Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else {
            bookmarks = []
            return
        }
        let decoder = HCGJSON.makeDecoder()
        guard let header = try? decoder.decode(FileHeader.self, from: data) else {
            setAsideCorrupt()
            return
        }
        switch header.version {
        case 1:
            guard let v1 = try? decoder.decode(FileContentsV1.self, from: data) else { setAsideCorrupt(); return }
            bookmarks = v1.bookmarks.map(\.migrated).sorted { $0.savedAt > $1.savedAt }
            let backup = fileURL.deletingPathExtension().appendingPathExtension("v1-backup").appendingPathExtension("json")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
            migratedFromVersion = 1
            try? persist()
        case Self.currentVersion:
            guard let contents = try? decoder.decode(FileContents.self, from: data) else { setAsideCorrupt(); return }
            bookmarks = contents.bookmarks.sorted { $0.savedAt > $1.savedAt }
        case let newer where newer > Self.currentVersion:
            // Best effort read of fields we know; never write.
            blockedByNewerVersion = newer
            bookmarks = ((try? decoder.decode(FileContents.self, from: data))?.bookmarks ?? []).sorted { $0.savedAt > $1.savedAt }
        default:
            setAsideCorrupt()
        }
    }

    private func setAsideCorrupt() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp)")
            .appendingPathExtension("json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        recoveredFromCorruption = true
        bookmarks = []
    }

    private func persist() throws {
        if let newer = blockedByNewerVersion { throw BookmarkStoreError.newerFileVersion(newer) }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try HCGJSON.makeEncoder().encode(
                FileContents(version: Self.currentVersion, bookmarks: bookmarks))
            #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: fileURL, options: [.atomic])
            #endif
        } catch {
            throw BookmarkStoreError.writeFailed(String(describing: type(of: error)))
        }
    }
}

/// Where the reader left off in each article (local only).
public struct ReadingPosition: Codable, Equatable, Sendable {
    /// Index of the top-most visible content block.
    public var blockIndex: Int
    public var updatedAt: Date

    public init(blockIndex: Int, updatedAt: Date) {
        self.blockIndex = blockIndex
        self.updatedAt = updatedAt
    }
}

/// Persists reading positions, keeping the most recent `limit` articles.
public actor ReadingPositionStore {
    struct FileContents: Codable {
        var version: Int
        var positions: [String: ReadingPosition]
    }

    private let fileURL: URL
    private let limit: Int
    private var positions: [String: ReadingPosition] = [:]
    private var loaded = false

    public init(fileURL: URL, limit: Int = 300) {
        self.fileURL = fileURL
        self.limit = limit
    }

    public static func defaultFileURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("HCGNews/reading-positions.json")
    }

    public func position(for id: ArticleID) -> ReadingPosition? {
        loadIfNeeded()
        return positions[id.rawValue]
    }

    public func setPosition(_ blockIndex: Int, for id: ArticleID, at date: Date = Date()) {
        loadIfNeeded()
        if blockIndex <= 0 {
            positions[id.rawValue] = nil
        } else {
            positions[id.rawValue] = ReadingPosition(blockIndex: blockIndex, updatedAt: date)
        }
        if positions.count > limit {
            let keep = positions.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(limit)
            positions = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        persist()
    }

    public func removeAll() {
        positions = [:]
        loaded = true
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let contents = try? HCGJSON.makeDecoder().decode(FileContents.self, from: data) else { return }
        positions = contents.positions
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? HCGJSON.makeEncoder().encode(FileContents(version: 1, positions: positions)) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}
