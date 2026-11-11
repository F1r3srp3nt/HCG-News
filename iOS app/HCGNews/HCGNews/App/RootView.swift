import SwiftUI
import NewsCore
import NewsAppModel

/// Chooses the layout from the horizontal size class, which already reflects
/// iPad Split View / Slide Over / Stage Manager window widths:
/// - compact (iPhone, narrow iPad windows): tab bar, one stack per tab;
/// - regular (iPad full screen and wide windows): sidebar + detail.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(Router.self) private var router
    @Environment(NewsAppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            #if DEBUG
            if env.isUsingTestFixtures { TestFixtureBanner() }
            #endif
            if sizeClass == .compact {
                CompactRootView()
            } else {
                RegularRootView()
            }
        }
        .onChange(of: sizeClass) { _, newValue in
            if newValue == .compact { router.adoptCompact() } else { router.adoptRegular() }
        }
    }
}

/// Destination screens shared by both layouts.
struct DestinationView: View {
    let destination: Destination

    var body: some View {
        switch destination {
        case .home: HomeView()
        case .sections: SectionsView()
        case .search: SearchView()
        case .saved: SavedView()
        }
    }
}

extension View {
    /// Registers article/section destinations on a navigation stack.
    func newsDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .article(let id):
                ArticleScreen(id: id)
            case .section(let slug, let name):
                SectionFeedView(slug: slug, name: name)
            }
        }
    }
}

// MARK: - Compact

struct CompactRootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            ForEach(Destination.allCases, id: \.self) { destination in
                NavigationStack(path: router.path(for: destination)) {
                    DestinationView(destination: destination)
                        .newsDestinations()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { router.isShowingSettings = true } label: {
                                    Label("Settings", systemImage: "gearshape")
                                }
                            }
                        }
                }
                .tabItem { Label(destination.title, systemImage: destination.systemImage) }
                .tag(destination)
            }
        }
        .sheet(isPresented: $router.isShowingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { router.isShowingSettings = false }
                        }
                    }
            }
            .hcgThemed()
        }
    }
}

// MARK: - Regular

struct RegularRootView: View {
    @Environment(Router.self) private var router
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.palette) private var palette
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    var body: some View {
        @Bindable var router = router
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: sidebarSelection) {
                Section {
                    ForEach(Destination.allCases, id: \.self) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(SidebarItem.destination(destination))
                    }
                }
                sidebarSections
                Section {
                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
            }
            .navigationTitle("HCG News")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { BrandMark(height: 24) }
            }
            .task { await env.sections.loadIfNeeded() }
        } detail: {
            NavigationStack(path: $router.detailPath) {
                detailRoot
                    .newsDestinations()
            }
            .id(router.sidebar)   // a new sidebar choice starts a fresh stack
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// Choosing a different sidebar item starts that destination fresh. Layout
    /// changes (rotation, Split View resizing) go through `Router.adoptRegular`
    /// instead and keep the reader's place.
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { router.sidebar },
            set: { newValue in
                guard newValue != router.sidebar else { return }
                router.detailPath = NavigationPath()
                router.sidebar = newValue
            })
    }

    @ViewBuilder
    private var sidebarSections: some View {
        if case .loaded(let nodes) = env.sections.state, !nodes.isEmpty {
            Section("Sections") {
                ForEach(nodes) { node in
                    Label(node.section.name, systemImage: "number")
                        .tag(SidebarItem.section(slug: node.section.slug, name: node.section.name))
                    ForEach(node.children) { child in
                        Text(child.name)
                            .padding(.leading, 28)
                            .tag(SidebarItem.section(slug: child.slug, name: child.name))
                            .accessibilityLabel("\(child.name), in \(node.section.name)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch router.sidebar {
        case .destination(let destination)?:
            DestinationView(destination: destination)
        case .section(let slug, let name)?:
            SectionFeedView(slug: slug, name: name)
        case .settings?:
            SettingsView()
        case nil:
            DestinationView(destination: .home)
        }
    }
}

#if DEBUG
/// Visible on every screen when UI-test fixtures are active, so fixture text
/// can never be mistaken for reporting.
struct TestFixtureBanner: View {
    var body: some View {
        Text("TEST FIXTURES — not live reporting")
            .font(.caption.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.orange)
            .foregroundStyle(Color.black)
            .accessibilityIdentifier("testFixtureBanner")
    }
}
#endif
