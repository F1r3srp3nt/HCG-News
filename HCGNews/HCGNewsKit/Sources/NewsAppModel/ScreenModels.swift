import Foundation
import Observation
import NewsCore
import HCGConnect

/// Articles loaded during this session. Used for search when the backend offers
/// none, and clearly labelled as such in the UI.
@MainActor
@Observable
public final class LoadedArticleIndex {
    private var order: [ArticleID] = []
    private var items: [ArticleID: ArticleSummary] = [:]

    public init() {}

    public func record(_ summaries: [ArticleSummary]) {
        for summary in summaries {
            if items[summary.id] == nil { order.append(summary.id) }
            items[summary.id] = summary
        }
    }

    public var all: [ArticleSummary] { order.compactMap { items[$0] } }
    public var count: Int { order.count }
    public func summary(for id: ArticleID) -> ArticleSummary? { items[id] }
}

// MARK: - Home

public struct HomeContent: Equatable, Sendable {
    public var featured: [ArticleSummary]
    public var breaking: [ArticleSummary]
    public var latest: [ArticleSummary]
    public var nextCursor: String?
}

@MainActor
@Observable
public final class HomeModel {
    public private(set) var state: LoadState<HomeContent> = .idle
    public private(set) var isLoadingMore = false
    public private(set) var loadMoreError: UserFacingError?
    public var breaking = BreakingCarousel(items: [])

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
        if state.value == nil { state = .loading }
        do {
            let feed = try await service.home()
            let featuredIDs = Set(feed.featured.map(\.id))
            // Featured stories are not repeated in the Latest list.
            let latest = feed.latest.items.filter { !featuredIDs.contains($0.id) }
            let content = HomeContent(featured: feed.featured, breaking: feed.breaking,
                                      latest: latest, nextCursor: feed.latest.nextCursor)
            index.record(feed.featured + feed.breaking + feed.latest.items)
            breaking = BreakingCarousel(items: feed.breaking, keepingCurrentFrom: breaking)
            state = .loaded(content)
            loadMoreError = nil
        } catch {
            // Keep showing already-loaded content when a refresh fails.
            if state.value == nil { state = .failed(UserFacingError(error)) } else { loadMoreError = UserFacingError(error) }
        }
    }

    public func loadMore() async {
        guard !isLoadingMore, var content = state.value, let cursor = content.nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.articles(sectionSlug: nil, cursor: cursor)
            let known = Set(content.latest.map(\.id) + content.featured.map(\.id))
            content.latest += page.items.filter { !known.contains($0.id) }
            content.nextCursor = page.nextCursor
            index.record(page.items)
            state = .loaded(content)
            loadMoreError = nil
        } catch {
            loadMoreError = UserFacingError(error)
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

    /// Groups sections under their parent (e.g. "Norwegian Politics" under "Politics")
    /// exactly as the backend defines them. Orphans become top-level entries.
    nonisolated public static func tree(_ sections: [NewsSection]) -> [SectionNode] {
        let slugs = Set(sections.map(\.slug))
        let roots = sections.filter { $0.parentSlug == nil || !slugs.contains($0.parentSlug!) }
        return roots.map { root in
            SectionNode(section: root, children: sections.filter { $0.parentSlug == root.slug })
        }
    }
}

@MainActor
@Observable
public final class ArticleListModel {
    public private(set) var state: LoadState<[ArticleSummary]> = .idle
    public private(set) var nextCursor: String?
    public private(set) var isLoadingMore = false
    public private(set) var loadMoreError: UserFacingError?

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
            state = .loaded(page.items)
            loadMoreError = nil
        } catch {
            if state.value == nil { state = .failed(UserFacingError(error)) } else { loadMoreError = UserFacingError(error) }
        }
    }

    public func loadMore() async {
        guard !isLoadingMore, let items = state.value, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.articles(sectionSlug: sectionSlug, cursor: cursor)
            let known = Set(items.map(\.id))
            index.record(page.items)
            nextCursor = page.nextCursor
            state = .loaded(items + page.items.filter { !known.contains($0.id) })
            loadMoreError = nil
        } catch {
            loadMoreError = UserFacingError(error)
        }
    }
}

// MARK: - Search

public enum SearchScope: Equatable, Sendable {
    /// Full-text search provided by the publication backend.
    case publication
    /// Only articles loaded on this device during this session.
    case loadedArticlesOnly
}

public struct SearchResults: Equatable, Sendable {
    public let query: String
    public let items: [ArticleSummary]
    public let scope: SearchScope
    public let nextCursor: String?
}

@MainActor
@Observable
public final class SearchModel {
    public private(set) var state: LoadState<SearchResults> = .idle
    public private(set) var scope: SearchScope?
    private let service: NewsService
    private let index: LoadedArticleIndex

    public init(service: NewsService, index: LoadedArticleIndex) {
        self.service = service
        self.index = index
    }

    /// Determines the search scope once. Falls back to loaded-article search
    /// (labelled) when the backend offers no search or cannot be reached.
    public func resolveScope() async -> SearchScope? {
        if let scope { return scope }
        do {
            scope = try await service.capabilities().serverSearch ? .publication : .loadedArticlesOnly
        } catch NewsServiceError.notConfigured {
            state = .failed(UserFacingError(NewsServiceError.notConfigured))
            return nil
        } catch {
            return .loadedArticlesOnly   // Not cached: retried on the next search.
        }
        return scope
    }

    public func search(_ rawQuery: String) async {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            state = .idle
            return
        }
        guard let scope = await resolveScope() else { return }
        switch scope {
        case .loadedArticlesOnly:
            state = .loaded(SearchResults(query: query, items: LocalArticleSearch.search(query, in: index.all),
                                          scope: .loadedArticlesOnly, nextCursor: nil))
        case .publication:
            state = .loading
            do {
                let page = try await service.search(query: query, cursor: nil)
                index.record(page.items)
                state = .loaded(SearchResults(query: query, items: page.items, scope: .publication, nextCursor: page.nextCursor))
            } catch {
                state = .failed(UserFacingError(error))
            }
        }
    }

    public func clear() { state = .idle }
}

// MARK: - Saved

@MainActor
@Observable
public final class SavedModel {
    public private(set) var bookmarks: [Bookmark] = []
    public private(set) var savedIDs: Set<ArticleID> = []
    public private(set) var lastError: String?
    public private(set) var recoveredFromCorruption = false
    private let store: BookmarkStore

    public init(store: BookmarkStore) { self.store = store }

    public func load() async {
        bookmarks = await store.all()
        savedIDs = Set(bookmarks.map(\.articleID))
        recoveredFromCorruption = await store.recoveredFromCorruption
    }

    public func isSaved(_ id: ArticleID) -> Bool { savedIDs.contains(id) }

    public func toggle(_ article: ArticleSummary) async {
        do {
            try await store.toggle(article)
            lastError = nil
        } catch {
            lastError = "The bookmark could not be saved on this device."
        }
        await load()
    }

    public func remove(_ id: ArticleID) async {
        do {
            try await store.remove(id)
            lastError = nil
        } catch {
            lastError = "The bookmark could not be removed."
        }
        await load()
    }

    /// Refreshes the stored snapshot (headline etc.) when a saved article is opened.
    public func refreshSnapshot(_ article: ArticleSummary) async {
        guard savedIDs.contains(article.id) else { return }
        try? await store.save(article)
        await load()
    }
}

// MARK: - Article

@MainActor
@Observable
public final class ArticleModel {
    public let id: ArticleID
    /// Summary known from the list the reader came from (shown while loading).
    public let preview: ArticleSummary?
    public private(set) var state: LoadState<Article> = .idle
    private let service: NewsService
    private let saved: SavedModel

    public init(id: ArticleID, preview: ArticleSummary?, service: NewsService, saved: SavedModel) {
        self.id = id
        self.preview = preview
        self.service = service
        self.saved = saved
    }

    public func load() async {
        state = .loading
        do {
            let article = try await service.article(id: id)
            state = .loaded(article)
            await saved.refreshSnapshot(article.summary)
        } catch {
            state = .failed(UserFacingError(error))
        }
    }

    public var isSaved: Bool { saved.isSaved(id) }

    /// Summary to save: the loaded article if available, otherwise the list preview.
    public var saveableSummary: ArticleSummary? { state.value?.summary ?? preview }

    public func toggleSaved() async {
        guard let summary = saveableSummary else { return }
        await saved.toggle(summary)
    }
}

// MARK: - Account

@MainActor
@Observable
public final class AccountModel {
    public private(set) var status: ConnectStatus?
    public private(set) var isWorking = false
    private let coordinator: HCGConnectCoordinator

    public init(coordinator: HCGConnectCoordinator) { self.coordinator = coordinator }

    public func refresh() async { status = await coordinator.status() }

    public func restore() async {
        await coordinator.restore()
        await refresh()
        if case .signedIn? = status?.authentication {
            await coordinator.checkAppAccess()
            await refresh()
        }
    }

    public func signIn() async {
        isWorking = true
        defer { isWorking = false }
        await coordinator.signIn()
        await refresh()
    }

    public func checkAccess() async {
        isWorking = true
        defer { isWorking = false }
        await coordinator.checkAppAccess()
        await refresh()
    }

    public func signOut() async {
        isWorking = true
        defer { isWorking = false }
        await coordinator.signOut()
        await refresh()
    }

    public func accessToken() async -> String? { await coordinator.validAccessToken() }

    /// Missing configuration fields, for the Settings screen.
    public var configurationProblems: [String] {
        switch status?.configuration {
        case .awaitingSetup?: return ConnectConfigurationLoader.requiredFields.map { "connect.\($0)" } + ["connect.approvedByFounder = true"]
        case .invalid(let problems)?: return problems
        default: return []
        }
    }
}
