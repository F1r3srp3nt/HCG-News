import Foundation
import HCGTransport

/// A locally saved article reference.
///
/// Keyed by the stable backend `ArticleID`. Stores only what the Saved list
/// needs to display (headline, section, date, canonical link). The article
/// body is NOT stored: saving is not an offline download in this milestone.
public struct Bookmark: Hashable, Codable, Sendable, Identifiable {
    public let articleID: ArticleID
    public var headline: String
    public var standfirst: String?
    public var sectionName: String?
    public var editorialType: String?
    public var bylineNames: String?
    public var publishedAt: Date?
    public var canonicalURL: URL?
    public let savedAt: Date

    public var id: ArticleID { articleID }

    public init(article: ArticleSummary, savedAt: Date = Date()) {
        articleID = article.id
        headline = article.headline
        standfirst = article.standfirst
        sectionName = article.section?.name
        editorialType = article.editorialType?.label
        bylineNames = article.bylineNames
        publishedAt = article.publishedAt
        canonicalURL = article.shareableURL
        self.savedAt = savedAt
    }
}

public enum BookmarkStoreError: Error, Equatable, Sendable {
    case writeFailed(String)
}

/// Persistent local bookmarks (JSON file in Application Support).
///
/// - No cloud synchronisation: there is no verified central bookmark contract.
/// - A corrupt file is preserved as `*.corrupt-<timestamp>.json` and the store
///   starts empty, so user data is never silently overwritten.
public actor BookmarkStore {
    struct FileContents: Codable {
        var version: Int
        var bookmarks: [Bookmark]
    }

    public static let currentVersion = 1

    private let fileURL: URL
    private var bookmarks: [Bookmark] = []
    private var loaded = false
    public private(set) var recoveredFromCorruption = false

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

    /// Saves (or refreshes the stored snapshot of) an article. Keeps the original save time.
    public func save(_ article: ArticleSummary, at date: Date = Date()) throws {
        loadIfNeeded()
        if let index = bookmarks.firstIndex(where: { $0.articleID == article.id }) {
            let original = bookmarks[index].savedAt
            bookmarks[index] = Bookmark(article: article, savedAt: original)
        } else {
            bookmarks.insert(Bookmark(article: article, savedAt: date), at: 0)
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
    public func toggle(_ article: ArticleSummary, at date: Date = Date()) throws -> Bool {
        if contains(article.id) {
            try remove(article.id)
            return false
        }
        try save(article, at: date)
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
        do {
            let contents = try HCGJSON.makeDecoder().decode(FileContents.self, from: data)
            bookmarks = contents.bookmarks.sorted { $0.savedAt > $1.savedAt }
        } catch {
            // Keep the unreadable file for recovery instead of overwriting it.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupt-\(stamp)")
                .appendingPathExtension("json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            recoveredFromCorruption = true
            bookmarks = []
        }
    }

    private func persist() throws {
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
