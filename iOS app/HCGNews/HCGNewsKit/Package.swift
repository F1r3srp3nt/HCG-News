// swift-tools-version: 6.0
import PackageDescription

// HCGNewsKit — UI-independent building blocks for the HCG News iPhone/iPad reader.
//
// - HCGTransport:  HTTP transport protocol, URLSession implementation, JSON date handling. Foundation only.
// - NewsCore:      article/section models, content-block parsing and HTML sanitising, publication
//                  visibility rules, breaking-news selection, local bookmarks, the news service
//                  protocol and the client for the PROPOSED HCG News content API. Foundation only.
// - HCGConnect:    HCG Connect native sign-in preparation: configuration validation, PKCE,
//                  authorization request/callback handling, token and App Access models, session
//                  coordination. No endpoints or client IDs are built in. Foundation only.
// - Newsroom:      local drafts (autosave, recovery, snapshots, export/import), and the
//                  capability-gated client for the PROPOSED newsroom API. Foundation only.
// - NewsAppModel:  observable screen models (Home, Sections, Search, Saved, Article, Account).
//                  Foundation + Observation.
//
// The SwiftUI app target lives in ../HCGNews and is built with Xcode on a Mac.
// Everything in this package also compiles and tests on Linux (swift:6.1 Docker image).
let package = Package(
    name: "HCGNewsKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HCGTransport", targets: ["HCGTransport"]),
        .library(name: "NewsCore", targets: ["NewsCore"]),
        .library(name: "HCGConnect", targets: ["HCGConnect"]),
        .library(name: "NewsAppModel", targets: ["NewsAppModel"]),
        .library(name: "Newsroom", targets: ["Newsroom"]),
    ],
    targets: [
        .target(name: "HCGTransport"),
        .target(name: "NewsCore", dependencies: ["HCGTransport"]),
        .target(name: "HCGConnect", dependencies: ["HCGTransport"]),
        .target(name: "Newsroom", dependencies: ["NewsCore", "HCGTransport"]),
        .target(name: "NewsAppModel", dependencies: ["NewsCore", "HCGConnect", "Newsroom"]),
        // Test-only helpers (fake transport, fictional fixtures). Not a product; never linked into the app.
        .target(name: "HCGTestSupport", dependencies: ["HCGTransport"], path: "Tests/HCGTestSupport"),
        .testTarget(name: "NewsCoreTests", dependencies: ["NewsCore", "HCGTransport", "HCGTestSupport"]),
        .testTarget(name: "HCGConnectTests", dependencies: ["HCGConnect", "HCGTransport", "HCGTestSupport"]),
        .testTarget(name: "NewsAppModelTests", dependencies: ["NewsAppModel", "NewsCore", "HCGConnect", "HCGTransport", "HCGTestSupport", "Newsroom"]),
        .testTarget(name: "NewsroomTests", dependencies: ["Newsroom", "NewsCore", "HCGTransport", "HCGTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
