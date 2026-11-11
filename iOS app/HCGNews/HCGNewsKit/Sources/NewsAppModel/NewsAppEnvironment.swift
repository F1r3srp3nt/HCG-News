import Foundation
import Observation
import NewsCore
import HCGConnect
import HCGTransport

/// Composition root shared by the iPhone and iPad layouts.
@MainActor
@Observable
public final class NewsAppEnvironment {
    public let contentConfiguration: NewsConfigurationState
    public let service: NewsService
    public let index: LoadedArticleIndex
    public let saved: SavedModel
    public let account: AccountModel
    public let home: HomeModel
    public let sections: SectionsModel
    public let search: SearchModel
    /// True only for DEBUG UI-test runs with labelled fixture content.
    public let isUsingTestFixtures: Bool

    @ObservationIgnored private var sectionFeeds: [String: ArticleListModel] = [:]

    public init(contentConfiguration: NewsConfigurationState,
                service: NewsService,
                bookmarks: BookmarkStore,
                connect: HCGConnectCoordinator,
                isUsingTestFixtures: Bool = false) {
        self.contentConfiguration = contentConfiguration
        self.service = service
        self.isUsingTestFixtures = isUsingTestFixtures
        let index = LoadedArticleIndex()
        self.index = index
        self.saved = SavedModel(store: bookmarks)
        self.account = AccountModel(coordinator: connect)
        self.home = HomeModel(service: service, index: index)
        self.sections = SectionsModel(service: service)
        self.search = SearchModel(service: service, index: index)
    }

    /// Builds the production environment from the bundled configuration file.
    /// With no approved configuration, the content service is `UnconfiguredNewsService`
    /// and HCG Connect is unavailable: the app then makes no HCG network requests.
    public static func live(configurationData: Data?,
                            expectedRedirectScheme: String,
                            transport: HTTPTransport,
                            browser: BrowserAuthenticating,
                            sessionStore: ConnectSessionStoring,
                            bookmarkFileURL: URL,
                            userAgent: String) -> NewsAppEnvironment {
        let contentState = NewsConfigurationLoader.load(configurationData)
        let connectState = ConnectConfigurationLoader.load(configurationData, expectedRedirectScheme: expectedRedirectScheme)
        let coordinator = HCGConnectCoordinator(configuration: connectState, browser: browser, store: sessionStore,
                                                transport: transport, userAgent: userAgent)
        let service: NewsService
        switch contentState {
        case .ready(let configuration):
            service = NewsAPIClient(configuration: configuration, transport: transport, userAgent: userAgent,
                                    accessToken: { await coordinator.validAccessToken() })
        case .awaitingSetup:
            service = UnconfiguredNewsService(reasons: ["No HCG News content API configuration is installed."])
        case .invalid(let problems):
            service = UnconfiguredNewsService(reasons: problems)
        }
        return NewsAppEnvironment(contentConfiguration: contentState, service: service,
                                  bookmarks: BookmarkStore(fileURL: bookmarkFileURL), connect: coordinator)
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
        ArticleModel(id: id, preview: index.summary(for: id), service: service, saved: saved)
    }

    /// Human-readable configuration problems for the "not connected" state.
    public var contentConfigurationProblems: [String] {
        switch contentConfiguration {
        case .ready: return []
        case .awaitingSetup: return ["No HCG News content API configuration is installed in this build."]
        case .invalid(let problems): return problems
        }
    }
}
