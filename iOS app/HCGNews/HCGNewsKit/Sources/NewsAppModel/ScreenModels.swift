import Foundation
import Observation
import NewsCore
import HCGConnect

/// Articles loaded during this session. Used for "This session" search and to
/// tell the offline library about newer versions of downloaded articles.
@MainActor
@Observable
public final class LoadedArticleIndex {
    private var order: [ArticleID] = []
    private var items: [ArticleID: ArticleSummary] = [:]
    /// Called with every batch recorded (e.g. to note newer versions of downloads).
    @ObservationIgnored public var observer: (([ArticleSummary]) -> Void)?

    public init() {}

    public func record(_ summaries: [ArticleSummary]) {
        for summary in summaries {
            if items[summary.id] == nil { order.append(summary.id) }
            items[summary.id] = summary
        }
        observer?(summaries)
    }

    public var all: [ArticleSummary] { order.compactMap { items[$0] } }
    public var count: Int { order.count }
    public func summary(for id: ArticleID) -> ArticleSummary? { items[id] }
}

/// Appends a page, keeping order and dropping articles already present.
public enum PageMerge {
    public static func append(_ page: [ArticleSummary], to existing: [ArticleSummary], excluding extra: Set<ArticleID> = []) -> [ArticleSummary] {
        var seen = Set(existing.map(\.id)).union(extra)
        return existing + page.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Home

public struct HomeContent: Equatable, Sendable {
    public var featured: [ArticleSummary]
    public var breaking: [ArticleSummary]
    public var latest: [ArticleSummary]
    public var nextCursor: String?

    /// Lead story: the first editorially featured article, else the newest article.
    public var lead: ArticleSummary? { featured.first ?? latest.first }
    /// True when the publication marked featured stories (only then is "Featured" shown).
    public var hasEditorialFeatured: Bool { !featured.isEmpty }
    public var isEmpty: Bool { featured.isEmpty && latest.isEmpty }
}

@MainActor
@Observable
public final class HomeModel {
    public private(set) var state: LoadState<HomeContent> = .idle
    public private(set) var isLoadingMore = false
    public private(set) var isRefreshing = false
    /// Error from the last refresh or "load more"; already-loaded content stays visible.
    public private(set) var refreshError: UserFacingError?
    public private(set) var lastUpdated: Date?
    public var breaking = BreakingCarousel(items: [])
    /// The article the reader last opened, to restore the scroll position.
    public var scrollAnchor: ArticleID?

    private let service: NewsService
    private let index: LoadedArticleIndex

    public init(service: NewsService, index: LoadedArticleIndex) {
        self.service = service
        self.index = index
    }

    public func loadIfNeeded() async {
        if case .idle = state { await reload() }
    }

    public func reload() async {
        if state.value == nil { state = .loading } else { isRefreshing = true }
        defer { isRefreshing = false }
        do {
            let feed = try await service.home()
            let featuredIDs = Set(feed.featured.map(\.id))
            let latest = PageMerge.append(feed.latest.items, to: [], excluding: featuredIDs)
            let content = HomeContent(featured: feed.featured, breaking: feed.breaking,
                                      latest: latest, nextCursor: feed.latest.nextCursor)
            index.record(feed.featured + feed.breaking + feed.latest.items)
            breaking = BreakingCarousel(items: feed.breaking, keepingCurrentFrom: breaking)
            state = .loaded(content)
            refreshError = nil
            lastUpdated = Date()
        } catch {
            // Keep showing already-loaded content when a refresh fails.
            if state.value == nil { state = .failed(UserFacingError(error)) } else { refreshError = UserFacingError(error) }
        }
    }

    public func loadMore() async {
        guard !isLoadingMore, var content = state.value, let cursor = content.nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.articles(sectionSlug: nil, cursor: cursor)
            content.latest = PageMerge.append(page.items, to: content.latest, excluding: Set(content.featured.map(\.id)))
            // A repeated cursor would loop forever: stop paginating instead.
            content.nextCursor = page.nextCursor == cursor ? nil : page.nextCursor
            index.record(page.items)
            state = .loaded(content)
            refreshError = nil
        } catch {
            refreshError = UserFacingError(error)
        }
    }
}

/// One breaking headline at a time with explicit previous/next navigation.
/// No automatic scrolling marquee.
public struct BreakingCarousel: Equatable, Sendable {
    public let items: [ArticleSummary]
    public private(set) var index: Int

    public init(items: [ArticleSummary]) {
        self.items = items
        self.index = 0
    }

    /// Keeps the reader on the same headline across refreshes when it is still breaking.
    public init(items: [ArticleSummary], keepingCurrentFrom previous: BreakingCarousel) {
        self.items = items
        if let currentID = previous.current?.id, let i = items.firstIndex(where: { $0.id == currentID }) {
            self.index = i
        } else {
            self.index = 0
        }
    }

    public var current: ArticleSummary? { items.indices.contains(index) ? items[index] : nil }
    public var hasMultiple: Bool { items.count > 1 }
    public var positionLabel: String { items.isEmpty ? "" : "\(index + 1) of \(items.count)" }

    public mutating func next() {
        guard !items.isEmpty else { return }
        index = (index + 1) % items.count
    }

    public mutating func previous() {
        guard !items.isEmpty else { return }
        index = (index - 1 + items.count) % items.count
    }
}

// MARK: - Sections

public struct SectionNode: Equatable, Sendable, Identifiable {
    public let section: NewsSection
    public let children: [NewsSection]
    public var id: String { section.id }
}

@MainActor
@Observable
public final class SectionsModel {
    public private(set) var state: LoadState<[SectionNode]> = .idle
    private let service: NewsService

    public init(service: NewsService) { self.service = service }

    public func loadIfNeeded() async {
        if case .idle = state { await reload() }
    }

    public func reload() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(Self.tree(try await service.sections()))
        } catch {
            if state.value == nil { state = .failed(UserFacingError(error)) }
        }
    }

    /// Groups sections under their parent exactly as the backend defines them.
    /// Sections with an unknown parent are kept as top-level entries, never dropped.
    nonisolated public static func tree(_ sections: [NewsSection]) -> [SectionNode] {
        let slugs = Set(sections.map(\.slug))
        let roots = sections.filter { $0.parentSlug == nil || !slugs.contains($0.parentSlug!) }
        return roots.map { root in
            SectionNode(section: root, children: sections.filter { $0.parentSlug == root.slug })
        }
    }

    public var allSections: [NewsSection] {
        (state.value ?? []).flatMap { [$0.section] + $0.children }
    }
}

@MainActor
@Observable
public final class ArticleListModel {
    public private(set) var state: LoadState<[ArticleSummary]> = .idle
    public private(set) var nextCursor: String?
    public private(set) var isLoadingMore = false
    public private(set) var refreshError: UserFacingError?
    public var scrollAnchor: ArticleID?

    public let sectionSlug: String?
    private let service: NewsService
    private let index: LoadedArticleIndex

    public init(sectionSlug: String?, service: NewsService, index: LoadedArticleIndex) {
        self.sectionSlug = sectionSlug
        self.service = service
        self.index = index
    }

    public func loadIfNeeded() async {
        if case .idle = state { await reload() }
    }

    public func reload() async {
        if state.value == nil { state = .loading }
        do {
            let page = try await service.articles(sectionSlug: sectionSlug, cursor: nil)
            index.record(page.items)
            nextCursor = page.nextCursor
            state = .loaded(PageMerge.append(page.items, to: []))
            refreshError = nil
        } catch {
            if state.value == nil { state = .failed(UserFacingError(error)) } else { refreshError = UserFacingError(error) }
        }
    }

    public func loadMore() async {
        guard !isLoadingMore, let items = state.value, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.articles(sectionSlug: sectionSlug, cursor: cursor)
            index.record(page.items)
            nextCursor = page.nextCursor == cursor ? nil : page.nextCursor
            state = .loaded(PageMerge.append(page.items, to: items))
            refreshError = nil
        } catch {
            refreshError = UserFacingError(error)
        }
    }
}

// MARK: - Search

public enum SearchScope: String, Equatable, Sendable, CaseIterable, Identifiable {
    /// Full-text search provided by the publication backend.
    case publication
    /// Only articles loaded on this device during this session.
    case loadedArticles
    /// Only articles downloaded for offline reading.
    case downloadedArticles

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .publication: "Publication"
        case .loadedArticles: "This session"
        case .downloadedArticles: "Downloaded"
        }
    }

    public var explanation: String {
        switch self {
        case .publication: "Searching the whole publication."
        case .loadedArticles: "Searching only articles loaded on this device during this session, not the full archive."
        case .downloadedArticles: "Searching only articles downloaded to this device. Works offline."
        }
    }
}

public struct SearchResults: Equatable, Sendable {
    public let query: String
    public let items: [ArticleSummary]
    public let scope: SearchScope
    public let nextCursor: String?
    /// Filters applied on the device because the server doesn't support them.
    /// The UI states that these only narrow the results already returned.
    public let locallyAppliedFilters: Set<SearchFilterKind>
}

@MainActor
@Observable
public final class SearchModel {
    public private(set) var state: LoadState<SearchResults> = .idle
    public private(set) var availableScopes: [SearchScope] = [.loadedArticles, .downloadedArticles]
    public private(set) var capabilities: NewsCapabilities?
    public var scope: SearchScope = .loadedArticles
    public var filters = SearchFilters()
    public private(set) var isLoadingMore = false

    private let service: NewsService
    private let index: LoadedArticleIndex
    private let downloaded: () async -> [ArticleSummary]
    private var scopesResolved = false

    public init(service: NewsService, index: LoadedArticleIndex, downloaded: @escaping () async -> [ArticleSummary]) {
        self.service = service
        self.index = index
        self.downloaded = downloaded
    }

    /// Finds out whether the publication offers server search. Downloaded-article
    /// search always works, even without a connection or configuration.
    public func resolveScopes() async {
        guard !scopesResolved else { return }
        do {
            let caps = try await service.capabilities()
            capabilities = caps
            scopesResolved = true
            availableScopes = caps.serverSearch ? [.publication, .loadedArticles, .downloadedArticles] : [.loadedArticles, .downloadedArticles]
            if caps.serverSearch { scope = .publication }
        } catch NewsServiceError.notConfigured, NewsServiceError.invalidConfiguration {
            scopesResolved = true
            availableScopes = [.downloadedArticles]
            scope = .downloadedArticles
        } catch {
            availableScopes = [.loadedArticles, .downloadedArticles]   // retried on the next search
        }
    }

    /// Filters the current scope runs on the server (others run on the device).
    public var serverFilterKinds: Set<SearchFilterKind> {
        scope == .publication ? (capabilities?.serverSearchFilters ?? []) : []
    }

    public func search(_ rawQuery: String) async {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            state = .idle
            return
        }
        await resolveScopes()
        if !availableScopes.contains(scope) { scope = availableScopes.first ?? .downloadedArticles }
        switch scope {
        case .loadedArticles:
            let items = LocalArticleSearch.search(query, in: index.all).filter { filters.matches($0) }
            state = .loaded(SearchResults(query: query, items: items, scope: .loadedArticles, nextCursor: nil, locallyAppliedFilters: []))
        case .downloadedArticles:
            let items = LocalArticleSearch.search(query, in: await downloaded()).filter { filters.matches($0) }
            state = .loaded(SearchResults(query: query, items: items, scope: .downloadedArticles, nextCursor: nil, locallyAppliedFilters: []))
        case .publication:
            state = .loading
            do {
                let page = try await service.search(query: query, filters: filters, cursor: nil)
                index.record(page.items)
                let local = filters.activeKinds.subtracting(serverFilterKinds)
                let items = page.items.filter { filters.matches($0, kinds: local) }
                state = .loaded(SearchResults(query: query, items: items, scope: .publication,
                                              nextCursor: page.nextCursor, locallyAppliedFilters: local))
            } catch {
                state = .failed(UserFacingError(error))
            }
        }
    }

    public func loadMore() async {
        guard !isLoadingMore, let results = state.value, results.scope == .publication, let cursor = results.nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.search(query: results.query, filters: filters, cursor: cursor)
            index.record(page.items)
            let items = page.items.filter { filters.matches($0, kinds: results.locallyAppliedFilters) }
            state = .loaded(SearchResults(query: results.query, items: PageMerge.append(items, to: results.items), scope: .publication,
                                          nextCursor: page.nextCursor == cursor ? nil : page.nextCursor,
                                          locallyAppliedFilters: results.locallyAppliedFilters))
        } catch {
            // Keep current results.
        }
    }

    public func clear() { state = .idle }
}

// MARK: - Saved and offline

@MainActor
@Observable
public final class SavedModel {
    public private(set) var bookmarks: [Bookmark] = []
    public private(set) var savedIDs: Set<ArticleID> = []
    public private(set) var downloads: [ArticleID: OfflineEntry] = [:]
    public private(set) var usageBytes: Int64 = 0
    public private(set) var lastError: String?
    public private(set) var recoveredFromCorruption = false
    public private(set) var migratedFromVersion: Int?
    public private(set) var newerFileVersion: Int?
    /// Storage limit for downloads (bytes). Set by the app from the reader's setting.
    public var limitBytes: Int64 = OfflineLibrary.defaultLimitBytes

    private let store: BookmarkStore
    let offline: OfflineLibrary
    private let fetcher: OfflineFetching?
    private let environment: String
    private var active: Set<ArticleID> = []

    /// - Parameter fetcher: nil when no publication is configured (downloads unavailable,
    ///   but existing downloads remain readable).
    public init(store: BookmarkStore, offline: OfflineLibrary, fetcher: OfflineFetching?, environment: String) {
        self.store = store
        self.offline = offline
        self.fetcher = fetcher
        self.environment = environment
    }

    public var canDownload: Bool { fetcher != nil }

    public func load() async {
        bookmarks = await store.all()
        savedIDs = Set(bookmarks.map(\.articleID))
        recoveredFromCorruption = await store.recoveredFromCorruption
        migratedFromVersion = await store.migratedFromVersion
        newerFileVersion = await store.newerFileVersion()
        await refreshDownloads()
    }

    public func refreshDownloads() async {
        let entries = await offline.entries()
        var map = Dictionary(uniqueKeysWithValues: entries.map { ($0.articleID, $0) })
        for id in active { map[id]?.state = .downloading }
        downloads = map
        usageBytes = await offline.usageBytes()
    }

    public func isSaved(_ id: ArticleID) -> Bool { savedIDs.contains(id) }
    public func download(for id: ArticleID) -> OfflineEntry? { downloads[id] }

    /// Saved articles that are downloaded, interrupted, failed or have updates, for badges.
    public var interruptedIDs: [ArticleID] {
        downloads.values.filter { $0.state == .interrupted }.map(\.articleID)
    }

    public func toggle(_ article: ArticleSummary) async {
        do {
            try await store.toggle(article, environment: environment)
            lastError = nil
        } catch BookmarkStoreError.newerFileVersion {
            lastError = "Saved articles were changed by a newer version of HCG News and can't be edited here."
        } catch {
            lastError = "The bookmark could not be saved on this device."
        }
        await load()
    }

    /// Removes the bookmark. A download is kept unless `alsoDownload` is true.
    public func remove(_ id: ArticleID, alsoDownload: Bool = false) async {
        do {
            try await store.remove(id)
            lastError = nil
        } catch {
            lastError = "The bookmark could not be removed."
        }
        if alsoDownload { await offline.remove(id) }
        await load()
    }

    /// Refreshes the stored snapshot (headline etc.) when a saved article is opened.
    public func refreshSnapshot(_ article: ArticleSummary) async {
        guard savedIDs.contains(article.id) else { return }
        try? await store.save(article, environment: environment)
        await load()
    }

    /// Saves (if needed) and downloads the article for offline reading.
    public func downloadArticle(_ summary: ArticleSummary) async {
        guard let fetcher else {
            lastError = "Downloads need a publication connection."
            return
        }
        guard !active.contains(summary.id) else { return }
        if !savedIDs.contains(summary.id) {
            try? await store.save(summary, environment: environment)
        }
        active.insert(summary.id)
        await load()
        let entry = await offline.download(summary.id, headline: summary.headline, environment: environment,
                                           using: fetcher, limitBytes: limitBytes)
        active.remove(summary.id)
        if case .failed(let reason) = entry.state { lastError = reason } else { lastError = nil }
        await load()
    }

    /// Resumes downloads interrupted by a crash or force-quit.
    public func resumeInterrupted() async {
        for id in interruptedIDs {
            let summary = bookmarks.first { $0.articleID == id }?.summary
                ?? ArticleSummary(id: id, headline: downloads[id]?.headline ?? "", publishedAt: nil)
            await downloadArticle(summary)
        }
    }

    public func removeDownload(_ id: ArticleID) async {
        await offline.remove(id)
        await refreshDownloads()
    }

    public func clearAllDownloads() async {
        await offline.removeAll()
        await refreshDownloads()
    }

    /// Summaries of downloaded articles (for offline search).
    public func downloadedSummaries() async -> [ArticleSummary] {
        var result: [ArticleSummary] = []
        for entry in await offline.entries() where entry.hasCompleteCopy {
            if let stored = await offline.storedArticle(entry.articleID) { result.append(stored.article.summary) }
        }
        return result
    }
}

// MARK: - Article

/// Where the article on screen came from.
public enum ArticleSource: Equatable, Sendable {
    /// Fetched from the publication just now.
    case live
    /// The copy stored on this device, shown because the live request failed or the
    /// publication isn't connected. Clearly labelled as a stored snapshot.
    case storedCopy(downloadedAt: Date, liveError: UserFacingError?)
}

public struct ArticlePresentation: Equatable, Sendable {
    public let article: Article
    public let source: ArticleSource
    /// True when the publication now has a newer version than the stored download.
    public let downloadUpdateAvailable: Bool
}

@MainActor
@Observable
public final class ArticleModel {
    public let id: ArticleID
    /// Summary known from the list the reader came from (shown while loading).
    public let preview: ArticleSummary?
    public private(set) var state: LoadState<ArticlePresentation> = .idle
    /// Block index to scroll to when the article opens (saved reading position).
    public private(set) var resumeBlockIndex: Int?

    private let service: NewsService
    private let saved: SavedModel
    private let positions: ReadingPositionStore

    public init(id: ArticleID, preview: ArticleSummary?, service: NewsService, saved: SavedModel, positions: ReadingPositionStore) {
        self.id = id
        self.preview = preview
        self.service = service
        self.saved = saved
        self.positions = positions
    }

    public func load() async {
        if state.value == nil { state = .loading }
        resumeBlockIndex = await positions.position(for: id)?.blockIndex
        do {
            let article = try await service.article(id: id)
            await saved.offline.noteLatest(marker: article.summary.contentVersionMarker, for: id)
            await saved.refreshDownloads()
            state = .loaded(ArticlePresentation(article: article, source: .live,
                                                downloadUpdateAvailable: saved.download(for: id)?.updateAvailable ?? false))
            await saved.refreshSnapshot(article.summary)
        } catch {
            let failure = UserFacingError(error)
            // Offline / server failure / no configuration: fall back to the stored copy.
            let fallbackKinds: Set<UserFacingError.Kind> = [.offline, .unavailable, .notConfigured, .invalidConfiguration, .rateLimited]
            if fallbackKinds.contains(failure.kind), let stored = await saved.offline.storedArticle(id) {
                state = .loaded(ArticlePresentation(article: stored.article,
                                                    source: .storedCopy(downloadedAt: stored.downloadedAt, liveError: failure),
                                                    downloadUpdateAvailable: false))
            } else {
                state = .failed(failure)
            }
        }
    }

    public func saveReadingPosition(_ blockIndex: Int) async {
        await positions.setPosition(blockIndex, for: id)
    }

    public var isSaved: Bool { saved.isSaved(id) }
    public var download: OfflineEntry? { saved.download(for: id) }
    public var canDownload: Bool {
        guard saved.canDownload, let value = state.value else { return false }
        return value.article.isEligibleForOfflineStorage
    }

    /// Summary to save: the loaded article if available, otherwise the list preview.
    public var saveableSummary: ArticleSummary? { state.value?.article.summary ?? preview }

    public func toggleSaved() async {
        guard let summary = saveableSummary else { return }
        await saved.toggle(summary)
    }

    public func downloadForOffline() async {
        guard let summary = saveableSummary else { return }
        await saved.downloadArticle(summary)
        if case .loaded(let value) = state {
            state = .loaded(ArticlePresentation(article: value.article, source: value.source, downloadUpdateAvailable: false))
        }
    }

    public func removeDownload() async {
        await saved.removeDownload(id)
    }
}
