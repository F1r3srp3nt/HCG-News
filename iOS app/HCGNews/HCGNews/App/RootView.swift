import SwiftUI
import NewsCore
import NewsAppModel

/// Chooses the layout from the horizontal size class, which reflects iPad Split
/// View / Slide Over / Stage Manager window widths.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(Router.self) private var router
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var router = router
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
        .onAppear { if sizeClass == .compact { router.isCompact = true } else { router.adoptRegular() } }
        .onChange(of: sizeClass) { _, newValue in
            if newValue == .compact { router.adoptCompact() } else { router.adoptRegular() }
        }
        .fullScreenCover(isPresented: $router.isShowingNewsroom) {
            NewsroomWorkspace()
                .environment(env)
                .environment(container)
                .environment(router)
                .hcgThemed()
        }
        .safeLinkHandling()
    }
}

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
    /// Registers reader and settings destinations on a navigation stack.
    func newsDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .article(let id): ArticleScreen(id: id)
            case .section(let slug, let name): SectionFeedView(slug: slug, name: name)
            }
        }
        .navigationDestination(for: SettingsRoute.self) { route in
            SettingsDestinationView(route: route)
        }
    }
}

// MARK: - Compact

struct CompactRootView: View {
    @Environment(Router.self) private var router
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            ForEach(Destination.allCases, id: \.self) { destination in
                NavigationStack(path: router.path(for: destination)) {
                    DestinationView(destination: destination)
                        .newsDestinations()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { router.showSettings() } label: {
                                    Label("Settings", systemImage: "person.crop.circle")
                                }
                            }
                        }
                }
                .tabItem { Label(destination.title, systemImage: destination.systemImage) }
                .tag(destination)
                .badge(destination == .saved ? env.saved.interruptedIDs.count : 0)
            }
        }
        .sheet(isPresented: $router.isShowingSettings, onDismiss: { router.settingsDidDismiss() }) {
            NavigationStack(path: $router.settingsPath) {
                SettingsView()
                    .newsDestinations()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { router.isShowingSettings = false }
                        }
                    }
            }
            .environment(env)
            .environment(container)
            .environment(router)
            .hcgThemed()
        }
    }
}

// MARK: - Regular

struct RegularRootView: View {
    @Environment(Router.self) private var router
    @Environment(NewsAppEnvironment.self) private var env
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    var body: some View {
        @Bindable var router = router
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: sidebarSelection) {
                Section {
                    ForEach(Destination.allCases, id: \.self) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .badge(destination == .saved ? env.saved.interruptedIDs.count : 0)
                            .tag(SidebarItem.destination(destination))
                    }
                }
                sidebarSections
                Section {
                    Label("Settings & Account", systemImage: "person.crop.circle")
                        .tag(SidebarItem.settings)
                    Button {
                        router.isShowingNewsroom = true
                    } label: {
                        Label("Newsroom", systemImage: "square.and.pencil")
                    }
                }
            }
            .navigationTitle("HCG News")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HCGMark(height: 22)
                        .padding(.horizontal, 4)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .task { await env.sections.loadIfNeeded() }
        } detail: {
            NavigationStack(path: $router.detailPath) {
                detailRoot.newsDestinations()
            }
            .id(router.sidebar)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// Choosing another sidebar item starts that destination fresh. Layout changes
    /// (rotation, Split View resizing) go through `Router.adoptRegular` instead.
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(get: { router.sidebar }, set: { newValue in
            guard newValue != router.sidebar else { return }
            router.detailPath = NavigationPath()
            router.sidebar = newValue
            if case .destination(let d)? = newValue { router.tab = d }
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
        case .destination(let destination)?: DestinationView(destination: destination)
        case .section(let slug, let name)?: SectionFeedView(slug: slug, name: name)
        case .settings?: SettingsView()
        case nil: DestinationView(destination: .home)
        }
    }
}

#if DEBUG
/// Visible on every screen when development fixtures are active, so fixture
/// text can never be mistaken for reporting.
struct TestFixtureBanner: View {
    var body: some View {
        Text("DEVELOPMENT FIXTURES — not live reporting")
            .font(.caption.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.orange)
            .foregroundStyle(Color.black)
            .accessibilityIdentifier("testFixtureBanner")
    }
}
#endif
