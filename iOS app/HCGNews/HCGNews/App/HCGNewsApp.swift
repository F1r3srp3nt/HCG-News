import SwiftUI
import NewsAppModel
import NewsCore
import HCGConnect
import HCGTransport

@main
struct HCGNewsApp: App {
    @State private var environment = AppBootstrap.makeEnvironment()
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(environment)
                .hcgThemed()
                .task {
                    await environment.saved.load()
                    await environment.account.restore()
                }
        }
    }
}

/// Builds the app's dependencies from the bundled configuration.
@MainActor
enum AppBootstrap {
    /// Bundle-identifier-based callback scheme (RFC 8252 §7.1 private-use scheme).
    /// The configured redirect URI must use exactly this scheme.
    static var callbackScheme: String { Bundle.main.bundleIdentifier ?? "com.hakmicapitalgroup.hcgnews" }

    static var userAgent: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "HCGNews-iOS/\(version) (\(build); \(UIDevice.current.systemName) \(UIDevice.current.systemVersion))"
    }

    /// `HCGNewsConfiguration.json` from the app bundle, if one is installed.
    /// The repository ships none: see docs/HCG-MAIN-CONFIGURATION-HANDOFF.md.
    static func bundledConfiguration() -> Data? {
        guard let url = Bundle.main.url(forResource: "HCGNewsConfiguration", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    static func makeEnvironment() -> NewsAppEnvironment {
        #if DEBUG
        if let fixtures = UITestFixtures.environmentIfRequested() { return fixtures }
        #endif
        let bookmarksURL = (try? BookmarkStore.defaultFileURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("bookmarks.json")
        return NewsAppEnvironment.live(
            configurationData: bundledConfiguration(),
            expectedRedirectScheme: callbackScheme,
            transport: URLSessionTransport(),
            browser: SystemBrowserAuthenticator(),
            sessionStore: KeychainSessionStore(),
            bookmarkFileURL: bookmarksURL,
            userAgent: userAgent)
    }
}
