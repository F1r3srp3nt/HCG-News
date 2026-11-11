import Foundation
import Observation
import NewsCore
import HCGConnect
import HCGTransport
import Newsroom

/// Platform pieces the app supplies (system browser, Keychain, network).
public struct PlatformServices: Sendable {
    public let transport: HTTPTransport
    public let browser: BrowserAuthenticating
    public let sessionStore: ConnectSessionStoring
    public let userAgent: String
    public let redirectScheme: String
    public let appVersion: String

    public init(transport: HTTPTransport, browser: BrowserAuthenticating, sessionStore: ConnectSessionStoring,
                userAgent: String, redirectScheme: String, appVersion: String) {
        self.transport = transport
        self.browser = browser
        self.sessionStore = sessionStore
        self.userAgent = userAgent
        self.redirectScheme = redirectScheme
        self.appVersion = appVersion
    }
}

/// Long-lived on-device stores. They survive configuration changes.
public struct LocalStores: Sendable {
    public let configuration: ConfigurationStore
    public let bookmarks: BookmarkStore
    public let offline: OfflineLibrary
    public let positions: ReadingPositionStore
    public let drafts: DraftStore
    public let log: LocalEventLog

    public init(configuration: ConfigurationStore, bookmarks: BookmarkStore, offline: OfflineLibrary,
                positions: ReadingPositionStore, drafts: DraftStore, log: LocalEventLog) {
        self.configuration = configuration
        self.bookmarks = bookmarks
        self.offline = offline
        self.positions = positions
        self.drafts = drafts
        self.log = log
    }

    /// Stores under a root folder (tests use a temporary directory).
    public static func rooted(at root: URL, bundledConfiguration: Data?, redirectScheme: String) -> LocalStores {
        LocalStores(
            configuration: ConfigurationStore(directory: root.appendingPathComponent("Configuration"),
                                              bundled: bundledConfiguration, expectedRedirectScheme: redirectScheme),
            bookmarks: BookmarkStore(fileURL: root.appendingPathComponent("bookmarks.json")),
            offline: OfflineLibrary(root: root.appendingPathComponent("Offline")),
            positions: ReadingPositionStore(fileURL: root.appendingPathComponent("reading-positions.json")),
            drafts: DraftStore(root: root.appendingPathComponent("Newsroom/Drafts")),
            log: LocalEventLog(fileURL: root.appendingPathComponent("event-log.json")))
    }
}

/// Everything built from the current configuration. Rebuilt by `AppContainer`
/// when a configuration is applied or removed.
@MainActor
@Observable
public final class NewsAppEnvironment {
    public let publicationConfiguration: NewsConfigurationState
    public let publicationSource: ConfigurationSource
    public let connectConfiguration: ConnectConfigurationState
    public let connectSource: ConfigurationSource
    public let service: NewsService
    public let index: LoadedArticleIndex
    public let saved: SavedModel
    public let account: AccountModel
    public let connection: ConnectionModel
    public let home: HomeModel
    public let sections: SectionsModel
    public let search: SearchModel
    public let newsroom: NewsroomModel
    public let admin: AdminModel
    public let stores: LocalStores
    /// True only for DEBUG UI-test runs with labelled fixture content.
    public let isUsingTestFixtures: Bool
    /// Bumped on every rebuild so views reset their navigation.
    public let generation: Int

    @ObservationIgnored private var sectionFeeds: [String: ArticleListModel] = [:]
    @ObservationIgnored public let connect: HCGConnectCoordinator

    public init(publication: (NewsConfigurationState, ConfigurationSource),
                connect connectConfig: (ConnectConfigurationState, ConfigurationSource),
                service: NewsService,
                newsroomService: NewsroomService,
                newsroomServiceConfigured: Bool,
                coordinator: HCGConnectCoordinator,
                stores: LocalStores,
                transport: HTTPTransport?,
                appVersion: String,
                isUsingTestFixtures: Bool = false,
                generation: Int = 0) {
        publicationConfiguration = publication.0
        publicationSource = publication.1
        connectConfiguration = connectConfig.0
        connectSource = connectConfig.1
        self.service = service
        self.stores = stores
        self.connect = coordinator
        self.isUsingTestFixtures = isUsingTestFixtures
        self.generation = generation

        let environmentName: String
        if case .ready(let c) = publication.0 { environmentName = c.environment } else { environmentName = isUsingTestFixtures ? "test-fixtures" : "none" }

        let index = LoadedArticleIndex()
        self.index = index
        let fetcher: OfflineFetching? = {
            guard let transport else { return nil }
            switch publication.0 {
            case .ready: return ServiceOfflineFetcher(service: service, transport: transport)
            default: return isUsingTestFixtures ? ServiceOfflineFetcher(service: service, transport: transport) : nil
            }
        }()
        let saved = SavedModel(store: stores.bookmarks, offline: stores.offline, fetcher: fetcher, environment: environmentName)
        self.saved = saved
        let offline = stores.offline
        index.observer = { summaries in
            Task { for s in summaries { await offline.noteLatest(marker: s.contentVersionMarker, for: s.id) } }
        }
        let account = AccountModel(coordinator: coordinator, log: stores.log)
        self.account = account
        connection = ConnectionModel(service: service, coordinator: coordinator, publicationState: publication.0,
                                     connectState: connectConfig.0, log: stores.log)
        home = HomeModel(service: service, index: index)
        sections = SectionsModel(service: service)
        search = SearchModel(service: service, index: index, downloaded: { await saved.downloadedSummaries() })
        let newsroomPermission = connectConfig.0.configuration?.newsroomPermission
        let newsroom = NewsroomModel(store: stores.drafts, service: newsroomService, environment: environmentName,
                                     generator: "HCG News iOS \(appVersion)", log: stores.log) { [weak account] in
            NewsroomAccess(serviceConfigured: newsroomServiceConfigured,
                           signedIn: account?.isSignedIn ?? false,
                           centralAccessGranted: account?.centralAccessGranted(permission: newsroomPermission) ?? false)
        }
        self.newsroom = newsroom
        admin = AdminModel(newsroom: newsroom, service: newsroomService, log: stores.log)
    }

    /// One list model per section, kept for the session so back-navigation keeps scroll state.
    public func feed(forSection slug: String?) -> ArticleListModel {
        let key = slug ?? "__all__"
        if let existing = sectionFeeds[key] { return existing }
        let model = ArticleListModel(sectionSlug: slug, service: service, index: index)
        sectionFeeds[key] = model
        return model
    }

    public func articleModel(id: ArticleID) -> ArticleModel {
        let preview = index.summary(for: id) ?? saved.bookmarks.first { $0.articleID == id }?.summary
        return ArticleModel(id: id, preview: preview, service: service, saved: saved, positions: stores.positions)
    }

    /// Human-readable problems for the not-connected / invalid states.
    public var contentConfigurationProblems: [String] {
        switch publicationConfiguration {
        case .ready: return []
        case .awaitingSetup: return ["No publication configuration is installed."]
        case .invalid(let problems): return problems
        }
    }

    public var newsroomPermission: String? { connectConfiguration.configuration?.newsroomPermission }
    public var managementLinks: [ManagementLink] { connectConfiguration.configuration?.managementLinks ?? [] }
    public var publicationURL: URL {
        if case .ready(let c) = publicationConfiguration { return c.publicationURL }
        return URL(string: "https://news.hakmicapitalgroup.com")!
    }
}

/// Owns the configuration store and rebuilds the environment when configuration changes.
@MainActor
@Observable
public final class AppContainer {
    public private(set) var environment: NewsAppEnvironment
    public private(set) var lastChangeMessage: String?

    @ObservationIgnored private let platform: PlatformServices
    @ObservationIgnored public let stores: LocalStores
    @ObservationIgnored private var generation = 0

    public init(platform: PlatformServices, stores: LocalStores) async {
        self.platform = platform
        self.stores = stores
        self.environment = await Self.build(platform: platform, stores: stores, generation: 0)
        await stores.offline.recoverInterrupted()
    }

    /// For DEBUG fixtures and previews.
    public init(fixedEnvironment: NewsAppEnvironment, platform: PlatformServices, stores: LocalStores) {
        self.platform = platform
        self.stores = stores
        self.environment = fixedEnvironment
    }

    static func build(platform: PlatformServices, stores: LocalStores, generation: Int) async -> NewsAppEnvironment {
        let publication = await stores.configuration.publicationState()
        let connect = await stores.configuration.connectState()
        let coordinator = HCGConnectCoordinator(configuration: connect.0, browser: platform.browser, store: platform.sessionStore,
                                                transport: platform.transport, userAgent: platform.userAgent)
        let service: NewsService
        var newsroomService: NewsroomService = UnavailableNewsroomService()
        var newsroomConfigured = false
        switch publication.0 {
        case .ready(let c):
            service = NewsAPIClient(configuration: c, transport: platform.transport, userAgent: platform.userAgent,
                                    accessToken: { await coordinator.validAccessToken() })
            if let base = c.newsroomAPIBaseURL {
                newsroomService = NewsroomAPIClient(baseURL: base, environment: c.environment, transport: platform.transport,
                                                    userAgent: platform.userAgent, token: { await coordinator.validAccessToken() })
                newsroomConfigured = true
            }
        case .awaitingSetup:
            service = UnconfiguredNewsService(reasons: ["No publication configuration is installed."])
        case .invalid(let problems):
            service = UnconfiguredNewsService(reasons: problems, invalid: true)
        }
        return NewsAppEnvironment(publication: publication, connect: connect, service: service,
                                  newsroomService: newsroomService, newsroomServiceConfigured: newsroomConfigured,
                                  coordinator: coordinator, stores: stores, transport: platform.transport,
                                  appVersion: platform.appVersion, generation: generation)
    }

    // MARK: Configuration changes

    public func preview(_ data: Data, as kind: ConfigurationKind) async -> ConfigurationImportPreview {
        await stores.configuration.preview(data, as: kind)
    }

    /// Applies a validated import. On failure the previous configuration stays active.
    public func apply(_ preview: ConfigurationImportPreview) async throws {
        let change = try await stores.configuration.apply(preview)
        await stores.log.record(.configuration, "\(preview.kind.title) configuration imported (\(preview.environment ?? "?"))")
        await handle(change)
    }

    /// Removes the imported configuration; the bundled one applies again, if any.
    public func remove(_ kind: ConfigurationKind) async {
        let change = await stores.configuration.remove(kind)
        await stores.log.record(.configuration, "\(kind.title) configuration removed")
        await handle(change)
    }

    private func handle(_ change: ConfigurationChange) async {
        if change.identityChanged {
            // A different identity setup: the old session and account data must not carry over.
            await environment.connect.forgetLocalSession()
            await stores.drafts.detachAllServerLinks(note: "The HCG Connect configuration changed, so this draft's newsroom link was removed. Your text and media are unchanged.")
            await stores.log.record(.account, "Identity configuration changed: local session and account links cleared")
            lastChangeMessage = "HCG Connect configuration changed. You've been signed out on this device, and newsroom links on local drafts were removed. Your drafts, saved articles and downloads are unchanged."
        } else {
            lastChangeMessage = "\(change.kind.title) configuration updated."
        }
        generation += 1
        environment = await Self.build(platform: platform, stores: stores, generation: generation)
        await environment.saved.load()
        await environment.account.restore()
    }

    public func clearChangeMessage() { lastChangeMessage = nil }

    public func diagnostics() async -> String {
        let publication = await stores.configuration.publicationState()
        let connect = await stores.configuration.connectState()
        return DiagnosticsReport.make(
            appVersion: platform.appVersion, publication: publication, connect: connect,
            publicationCheck: environment.connection.publicationSummary,
            connectCheck: environment.connection.connectSummary,
            offlineCount: await stores.offline.entries().filter(\.hasCompleteCopy).count,
            offlineBytes: await stores.offline.usageBytes(),
            events: await stores.log.all())
    }
}
