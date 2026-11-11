import SwiftUI
import Observation
import NewsCore

/// Values pushed onto a navigation stack.
enum Route: Hashable {
    case article(ArticleID)
    case section(slug: String, name: String)
}

/// Top-level destinations (tabs on iPhone / compact width, sidebar on iPad).
enum Destination: String, Hashable, CaseIterable {
    case home, sections, search, saved

    var title: String {
        switch self {
        case .home: "Home"
        case .sections: "Sections"
        case .search: "Search"
        case .saved: "Saved"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "newspaper"
        case .sections: "list.bullet.rectangle"
        case .search: "magnifyingglass"
        case .saved: "bookmark"
        }
    }
}

/// Sidebar selection on regular width. Sections appear directly in the sidebar.
enum SidebarItem: Hashable {
    case destination(Destination)
    case section(slug: String, name: String)
    case settings
}

/// Navigation state shared by the compact and regular layouts, so that rotating
/// an iPad or resizing a Split View window keeps the reader's place.
@MainActor
@Observable
final class Router {
    var tab: Destination = .home
    var paths: [Destination: NavigationPath] = [:]
    var sidebar: SidebarItem? = .destination(.home)
    var detailPath = NavigationPath()
    var isShowingSettings = false

    func path(for destination: Destination) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[destination] ?? NavigationPath() },
            set: { self.paths[destination] = $0 })
    }

    /// Opens an article from anywhere (e.g. a breaking headline).
    func open(_ route: Route, compact: Bool) {
        if compact {
            var path = paths[tab] ?? NavigationPath()
            path.append(route)
            paths[tab] = path
        } else {
            detailPath.append(route)
        }
    }

    /// Moves state from the tab layout to the sidebar layout.
    func adoptRegular() {
        sidebar = .destination(tab)
        detailPath = paths[tab] ?? NavigationPath()
    }

    /// Moves state from the sidebar layout to the tab layout.
    func adoptCompact() {
        switch sidebar {
        case .destination(let d)?:
            tab = d
            paths[d] = detailPath
        case .section(let slug, let name)?:
            tab = .sections
            var path = NavigationPath()
            path.append(Route.section(slug: slug, name: name))
            paths[.sections] = path
        case .settings?:
            isShowingSettings = true
        case nil:
            break
        }
    }

}
