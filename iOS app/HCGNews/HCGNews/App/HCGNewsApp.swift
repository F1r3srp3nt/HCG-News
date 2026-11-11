import SwiftUI
import NewsAppModel
import NewsCore
import HCGConnect
import HCGTransport
import Newsroom

@main
struct HCGNewsApp: App {
    @State private var container: AppContainer?
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    ContainerRoot(container: container)
                } else {
                    LaunchView()
                        .task { container = await AppBootstrap.makeContainer() }
                }
            }
            .environment(router)
            .hcgThemed()
        }
        .commands { NewsCommands(router: router) }
    }
}

/// Injects the current environment; a configuration change rebuilds it and resets navigation.
struct ContainerRoot: View {
    let container: AppContainer
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let environment = container.environment
        let offline = container.stores.offline
        RootView()
            .id(environment.generation)
            .environment(container)
            .environment(environment)
            .environment(\.offlineImageResolver, OfflineImageResolver { url in await offline.localImage(for: url) })
            .task(id: environment.generation) {
                await environment.saved.load()
                await environment.account.restore()
            }
            .onChange(of: environment.generation) { _, _ in router.reset() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await environment.saved.refreshDownloads() } }
            }
    }
}

/// Shown while on-device stores open (normally a fraction of a second).
struct LaunchView: View {
    var body: some View {
        ZStack {
            Palette.masthead.ignoresSafeArea()
            HCGMark(height: 72)
        }
        .accessibilityLabel("HCG News is opening")
    }
}

@MainActor
enum AppBootstrap {
    /// Bundle-identifier-based callback scheme (RFC 8252 §7.1 private-use scheme).
    static var callbackScheme: String { Bundle.main.bundleIdentifier ?? "com.hakmicapitalgroup.hcgnews" }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    static var userAgent: String {
        "HCGNews-iOS/\(appVersion) (\(UIDevice.current.systemName) \(UIDevice.current.systemVersion))"
    }

    /// Optional bundled configuration (`HCGNews/Configuration/HCGNewsConfiguration.json`).
    /// The repository ships none. Imported configurations take precedence.
    static func bundledConfiguration() -> Data? {
        guard let url = Bundle.main.url(forResource: "HCGNewsConfiguration", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    static func makeContainer() async -> AppContainer {
        #if DEBUG
        if let fixtures = UITestFixtures.containerIfRequested() { return fixtures }
        #endif
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let stores = LocalStores.rooted(at: support.appendingPathComponent("HCGNews", isDirectory: true),
                                        bundledConfiguration: bundledConfiguration(), redirectScheme: callbackScheme)
        let platform = PlatformServices(transport: URLSessionTransport(), browser: SystemBrowserAuthenticator(),
                                        sessionStore: KeychainSessionStore(), userAgent: userAgent,
                                        redirectScheme: callbackScheme, appVersion: appVersion)
        return await AppContainer(platform: platform, stores: stores)
    }
}
