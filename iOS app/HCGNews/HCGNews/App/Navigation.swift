import SwiftUI
import Observation
import NewsCore

/// Values pushed onto a reader navigation stack.
enum Route: Hashable {
    case article(ArticleID)
    case section(slug: String, name: String)
}

/// Destinations inside Settings.
enum SettingsRoute: Hashable {
    case account
    case reading
    case notifications
    case storage
    case advanced
    case importConfiguration
    case diagnostics
    case about
}

/// Reader destinations (tabs on iPhone / compact width, sidebar on iPad).
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
        case .sections: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .saved: "bookmark"
        }
    }
}

enum SidebarItem: Hashable {
    case destination(Destination)
    case section(slug: String, name: String)
    case settings
}

/// Navigation state shared by both layouts, so rotating an iPad or resizing a
/// Split View window keeps the reader's place.
@MainActor
@Observable
final class Router {
    var tab: Destination = .home
    var paths: [Destination: NavigationPath] = [:]
    var sidebar: SidebarItem? = .destination(.home)
    var detailPath = NavigationPath()
    var isShowingSettings = false
    var settingsPath = NavigationPath()
    var isShowingNewsroom = false
    /// Set while Settings (a sheet on iPhone) closes, so the Newsroom cover opens
    /// only after the sheet has finished dismissing.
    var openNewsroomAfterSettings = false
    /// Incremented to ask Search to focus its field (⌘F).
    var searchFocusRequest = 0
    var isCompact = true

    func path(for destination: Destination) -> Binding<NavigationPath> {
        Binding(get: { self.paths[destination] ?? NavigationPath() }, set: { self.paths[destination] = $0 })
    }

    func select(_ destination: Destination) {
        tab = destination
        if sidebar != .destination(destination) {
            detailPath = NavigationPath()
            sidebar = .destination(destination)
        }
    }

    func focusSearch() {
        select(.search)
        searchFocusRequest += 1
    }

    func open(_ route: Route) {
        if isCompact {
            var path = paths[tab] ?? NavigationPath()
            path.append(route)
            paths[tab] = path
        } else {
            detailPath.append(route)
        }
    }

    func showSettings(_ route: SettingsRoute? = nil) {
        var path = NavigationPath()
        if let route { path.append(route) }
        if isCompact {
            settingsPath = path
            isShowingSettings = true
        } else {
            sidebar = .settings
            detailPath = path
        }
    }

    func showAdvancedSettings() { showSettings(.advanced) }

    /// Opens the Newsroom from Settings without presenting over a dismissing sheet.
    func openNewsroomFromSettings() {
        if isCompact && isShowingSettings {
            openNewsroomAfterSettings = true
            isShowingSettings = false
        } else {
            isShowingNewsroom = true
        }
    }

    /// Called from the Settings sheet's onDismiss.
    func settingsDidDismiss() {
        if openNewsroomAfterSettings {
            openNewsroomAfterSettings = false
            isShowingNewsroom = true
        }
    }

    /// Moves state from the tab layout to the sidebar layout.
    func adoptRegular() {
        isCompact = false
        if isShowingSettings {
            isShowingSettings = false
            sidebar = .settings
            detailPath = settingsPath
        } else {
            sidebar = .destination(tab)
            detailPath = paths[tab] ?? NavigationPath()
        }
    }

    /// Moves state from the sidebar layout to the tab layout.
    func adoptCompact() {
        isCompact = true
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
            settingsPath = detailPath
            isShowingSettings = true
        case nil:
            break
        }
    }

    func reset() {
        paths = [:]
        detailPath = NavigationPath()
        settingsPath = NavigationPath()
    }
}

/// Keyboard shortcuts (iPad with a hardware keyboard).
struct NewsCommands: Commands {
    let router: Router

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Home") { router.select(.home) }.keyboardShortcut("1", modifiers: .command)
            Button("Sections") { router.select(.sections) }.keyboardShortcut("2", modifiers: .command)
            Button("Search") { router.focusSearch() }.keyboardShortcut("f", modifiers: .command)
            Button("Saved") { router.select(.saved) }.keyboardShortcut("3", modifiers: .command)
            Divider()
            Button("Settings") { router.showSettings() }.keyboardShortcut(",", modifiers: .command)
            Button("Newsroom") { router.isShowingNewsroom = true }.keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}
