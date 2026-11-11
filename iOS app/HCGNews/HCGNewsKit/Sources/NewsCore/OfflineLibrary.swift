import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport

/// State of one offline download.
public enum DownloadState: Equatable, Codable, Sendable {
    /// In progress. Persisted, so a crash or force-quit is detected at next launch.
    case downloading
    /// Complete; readable without a connection.
    case downloaded
    /// The last attempt failed. A previous complete copy, if any, is still kept.
    case failed(reason: String)
    /// The app quit during a download. Can be resumed.
    case interrupted
}

/// Manifest entry for one article.
public struct OfflineEntry: Equatable, Codable, Sendable, Identifiable {
    public let articleID: ArticleID
    public var headline: String
    public var state: DownloadState
    /// When the stored copy was downloaded. Nil when no complete copy exists.
    public var downloadedAt: Date?
    /// Content marker (revision or update time) of the stored copy.
    public var storedMarker: String?
    /// Latest marker seen online. When it differs from `storedMarker`, an update is available.
    public var latestKnownMarker: String?
    public var bytes: Int64
    public var imageCount: Int
    /// Images that could not be downloaded; the article text is still complete.
    public var missingImages: Int
    /// Configuration environment the copy came from (e.g. "beta").
    public var environment: String

    public var id: ArticleID { articleID }
    public var hasCompleteCopy: Bool { downloadedAt != nil }

    /// True only when the publication reported a different version than the stored one.
    public var updateAvailable: Bool {
        guard hasCompleteCopy, let latest = latestKnownMarker, let stored = storedMarker else { return false }
        return latest != stored
    }
}

/// A stored copy as read back from disk.
public struct StoredArticle: Equatable, Sendable {
    public let article: Article
    public let downloadedAt: Date
    public let environment: String
}

public enum OfflineError: Error, Equatable, Sendable {
    case notEligible(String)
    case storageLimitReached(limitBytes: Int64)
    case writeFailed
}

/// Fetches what a download needs. The app uses the configured news service and
/// the HTTP transport; tests inject fakes.
public protocol OfflineFetching: Sendable {
    func article(id: ArticleID) async throws -> Article
    func imageData(from url: URL) async throws -> Data
}

/// Fetcher backed by the news service and an HTTPS transport.
public struct ServiceOfflineFetcher: OfflineFetching {
    let service: NewsService
    let transport: HTTPTransport

    public init(service: NewsService, transport: HTTPTransport) {
        self.service = service
        self.transport = transport
    }

    public func article(id: ArticleID) async throws -> Article { try await service.article(id: id) }

    public func imageData(from url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw TransportError.insecureConnection }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode), !data.isEmpty else {
            throw TransportError.other("HTTP \(response.statusCode)")
        }
        return data
    }
}

/// Downloaded articles for offline reading (Application Support, not backed up as a cache).
///
/// Layout: `<root>/manifest.json`, `<root>/articles/<key>/article.json`, `<root>/articles/<key>/images/*`.
/// - A new download is written to a temporary folder and swapped in only when complete,
///   so a failed update never destroys the previous good copy.
/// - `downloading` is persisted before any network work; at the next launch it becomes
///   `interrupted` (see `recoverInterrupted`).
/// - Only full-content public articles are stored. Restricted articles are refused until
///   an access policy for offline copies is agreed.
/// - Bookmarks are separate: removing a download never removes a bookmark.
public actor OfflineLibrary {
    struct Manifest: Codable {
        var version: Int
        var entries: [OfflineEntry]
    }

    public static let manifestVersion = 1
    public static let defaultLimitBytes: Int64 = 500 * 1024 * 1024

    private let root: URL
    private var manifest = Manifest(version: OfflineLibrary.manifestVersion, entries: [])
    private var loaded = false
    private let now: @Sendable () -> Date

    public init(root: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root
        self.now = now
    }

    public static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("HCGNews/Offline", isDirectory: true)
    }

    // MARK: Queries

    public func entries() -> [OfflineEntry] {
        loadIfNeeded()
        return manifest.entries
    }

    public func entry(for id: ArticleID) -> OfflineEntry? {
        loadIfNeeded()
        return manifest.entries.first { $0.articleID == id }
    }

    /// Total bytes used by stored copies.
    public func usageBytes() -> Int64 {
        loadIfNeeded()
        return manifest.entries.reduce(0) { $0 + $1.bytes }
    }

    /// The stored copy, if a complete one exists.
    public func storedArticle(_ id: ArticleID) -> StoredArticle? {
        loadIfNeeded()
        guard let entry = entry(for: id), let downloadedAt = entry.downloadedAt,
              let data = try? Data(contentsOf: articleDirectory(id).appendingPathComponent("article.json")),
              let article = try? HCGJSON.makeDecoder().decode(Article.self, from: data)
        else { return nil }
        return StoredArticle(article: article, downloadedAt: downloadedAt, environment: entry.environment)
    }

    /// Local file for a remote image of a stored article, if it was downloaded.
    public func localImage(for remote: URL, article id: ArticleID) -> URL? {
        let url = articleDirectory(id).appendingPathComponent("images").appendingPathComponent(Self.imageFileName(remote))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Local file for a remote image of any stored article.
    public func localImage(for remote: URL) -> URL? {
        loadIfNeeded()
        for entry in manifest.entries where entry.hasCompleteCopy {
            if let url = localImage(for: remote, article: entry.articleID) { return url }
        }
        return nil
    }

    // MARK: Launch recovery

    /// Turns downloads left `downloading` by a crash or force-quit into `interrupted`,
    /// removes their temporary folders, and returns their ids.
    @discardableResult
    public func recoverInterrupted() -> [ArticleID] {
        loadIfNeeded()
        var ids: [ArticleID] = []
        for index in manifest.entries.indices where manifest.entries[index].state == .downloading {
            manifest.entries[index].state = .interrupted
            ids.append(manifest.entries[index].articleID)
            try? FileManager.default.removeItem(at: temporaryDirectory(manifest.entries[index].articleID))
        }
        // An entry with neither a copy nor a recoverable state is dropped.
        if !ids.isEmpty { try? persist() }
        return ids
    }

    // MARK: Updates

    /// Records the latest marker seen online (e.g. from a list or the live article).
    public func noteLatest(marker: String?, for id: ArticleID) {
        loadIfNeeded()
        guard let marker, let index = manifest.entries.firstIndex(where: { $0.articleID == id }),
              manifest.entries[index].latestKnownMarker != marker else { return }
        manifest.entries[index].latestKnownMarker = marker
        try? persist()
    }

    // MARK: Download

    /// Downloads (or updates) an article and its images.
    /// Returns the resulting entry; on failure the entry is `failed` and any previous copy is kept.
    @discardableResult
    public func download(_ id: ArticleID, headline: String, environment: String, using fetcher: OfflineFetching,
                         limitBytes: Int64 = OfflineLibrary.defaultLimitBytes) async -> OfflineEntry {
        loadIfNeeded()
        upsert(id) { entry in
            entry.state = .downloading
            if entry.headline.isEmpty { entry.headline = headline }
        }
        try? persist()

        let temp = temporaryDirectory(id)
        let fm = FileManager.default
        try? fm.removeItem(at: temp)

        do {
            let article = try await fetcher.article(id: id)
            guard article.isEligibleForOfflineStorage else {
                let reason: String
                if article.summary.access != .public {
                    reason = "Restricted articles aren't stored for offline reading."
                } else if article.completeness == .summaryOnly {
                    reason = "Only a summary is available, so there is nothing to download."
                } else {
                    reason = "This article has no text to download."
                }
                throw OfflineError.notEligible(reason)
            }
            try fm.createDirectory(at: temp.appendingPathComponent("images"), withIntermediateDirectories: true)
            let urls = article.imageURLs
            var missing = 0
            var bytes: Int64 = 0
            for url in urls {
                do {
                    let data = try await fetcher.imageData(from: url)
                    try data.write(to: temp.appendingPathComponent("images").appendingPathComponent(Self.imageFileName(url)))
                    bytes += Int64(data.count)
                } catch {
                    missing += 1
                }
            }
            let json = try HCGJSON.makeEncoder().encode(article)
            bytes += Int64(json.count)

            let others = manifest.entries.filter { $0.articleID != id }.reduce(Int64(0)) { $0 + $1.bytes }
            guard others + bytes <= limitBytes else { throw OfflineError.storageLimitReached(limitBytes: limitBytes) }

            try json.write(to: temp.appendingPathComponent("article.json"), options: [.atomic])
            // Swap the complete copy in.
            let final = articleDirectory(id)
            try? fm.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: final)
            try fm.moveItem(at: temp, to: final)
            excludeFromBackup(final)

            let marker = article.summary.contentVersionMarker
            upsert(id) { entry in
                entry.headline = article.summary.headline
                entry.state = .downloaded
                entry.downloadedAt = now()
                entry.storedMarker = marker
                entry.latestKnownMarker = marker
                entry.bytes = bytes
                entry.imageCount = urls.count
                entry.missingImages = missing
                entry.environment = environment
            }
        } catch {
            try? fm.removeItem(at: temp)
            upsert(id) { $0.state = .failed(reason: Self.describe(error)) }
        }
        try? persist()
        return entry(for: id)!
    }

    // MARK: Removal

    /// Removes the stored copy (the bookmark, if any, is unaffected).
    public func remove(_ id: ArticleID) {
        loadIfNeeded()
        try? FileManager.default.removeItem(at: articleDirectory(id))
        try? FileManager.default.removeItem(at: temporaryDirectory(id))
        manifest.entries.removeAll { $0.articleID == id }
        try? persist()
    }

    public func removeAll() {
        loadIfNeeded()
        try? FileManager.default.removeItem(at: root.appendingPathComponent("articles"))
        try? FileManager.default.removeItem(at: root.appendingPathComponent("tmp"))
        manifest.entries = []
        try? persist()
    }

    /// Removes copies of articles that the publication no longer returns (unpublished).
    public func removeUnavailable(_ id: ArticleID) { remove(id) }

    // MARK: Internals

    private func upsert(_ id: ArticleID, _ change: (inout OfflineEntry) -> Void) {
        if let index = manifest.entries.firstIndex(where: { $0.articleID == id }) {
            change(&manifest.entries[index])
        } else {
            var entry = OfflineEntry(articleID: id, headline: "", state: .downloading, downloadedAt: nil,
                                     storedMarker: nil, latestKnownMarker: nil, bytes: 0, imageCount: 0,
                                     missingImages: 0, environment: "")
            change(&entry)
            manifest.entries.insert(entry, at: 0)
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")) else { return }
        if let decoded = try? HCGJSON.makeDecoder().decode(Manifest.self, from: data), decoded.version <= Self.manifestVersion {
            manifest = decoded
        } else {
            // Unreadable or newer manifest: keep it aside, start empty, never overwrite it.
            let aside = root.appendingPathComponent("manifest.unreadable-\(Int(now().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: root.appendingPathComponent("manifest.json"), to: aside)
        }
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try HCGJSON.makeEncoder().encode(manifest)
        try data.write(to: root.appendingPathComponent("manifest.json"), options: [.atomic])
    }

    private func articleDirectory(_ id: ArticleID) -> URL {
        root.appendingPathComponent("articles", isDirectory: true).appendingPathComponent(Self.key(id), isDirectory: true)
    }

    private func temporaryDirectory(_ id: ArticleID) -> URL {
        root.appendingPathComponent("tmp", isDirectory: true).appendingPathComponent(Self.key(id), isDirectory: true)
    }

    private func excludeFromBackup(_ url: URL) {
        #if os(iOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var copy = url
        try? copy.setResourceValues(values)
        #endif
    }

    /// File-system-safe key for an article id.
    static func key(_ id: ArticleID) -> String {
        id.rawValue.utf8.map { String(format: "%02x", $0) }.joined()
    }

    /// Stable file name for an image URL (FNV-1a 64 + extension).
    static func imageFileName(_ url: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let ext = url.pathExtension.lowercased()
        let safeExt = ["jpg", "jpeg", "png", "webp", "gif", "heic"].contains(ext) ? ext : "img"
        return String(format: "%016llx", hash) + "." + safeExt
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case OfflineError.notEligible(let reason): return reason
        case OfflineError.storageLimitReached(let limit):
            return "Offline storage limit reached (\(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file))). Remove downloads or raise the limit."
        case NewsServiceError.offline: return "You're offline."
        case NewsServiceError.notFound: return "The article is no longer available."
        case NewsServiceError.restricted, NewsServiceError.forbidden: return "This article requires HCG access."
        case NewsServiceError.notConfigured: return "The publication is not connected."
        default: return "The download failed. Try again."
        }
    }
}
