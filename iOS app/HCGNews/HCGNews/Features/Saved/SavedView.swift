import SwiftUI
import NewsCore
import NewsAppModel

/// Locally saved articles (this device only, keyed by stable article ID).
struct SavedView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.palette) private var palette

    var body: some View {
        let saved = env.saved
        List {
            Section {
                OfflineNotice()
                    .listRowBackground(Color.clear)
                if saved.recoveredFromCorruption {
                    Text("Your saved list couldn't be read and was set aside. Articles saved from now on will appear here.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .listRowBackground(Color.clear)
                }
                if let error = saved.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
            }

            if saved.bookmarks.isEmpty {
                Section {
                    MessageStateView(title: "No saved articles",
                                     message: "Tap the bookmark button while reading to save an article here.",
                                     systemImage: "bookmark")
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(saved.bookmarks) { bookmark in
                        NavigationLink(value: Route.article(bookmark.articleID)) {
                            SavedRow(bookmark: bookmark)
                        }
                        .listRowBackground(palette.surface)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { saved.bookmarks[$0].articleID }
                        Task { for id in ids { await saved.remove(id) } }
                    }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Saved")
        .toolbar {
            if !saved.bookmarks.isEmpty { EditButton() }
        }
        .task { await saved.load() }
    }
}

struct OfflineNotice: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Label {
            Text("Saved articles are stored on this device only. Article text isn't downloaded, so you need a connection to read them.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
        } icon: {
            Image(systemName: "iphone").foregroundStyle(palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SavedRow: View {
    let bookmark: Bookmark
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let kicker = [bookmark.editorialType?.uppercased(), bookmark.sectionName].compactMap { $0 }
            if !kicker.isEmpty {
                Text(kicker.joined(separator: " · "))
                    .font(Typography.kicker)
                    .foregroundStyle(palette.accent)
            }
            Text(bookmark.headline)
                .font(Typography.headline(.headline))
                .foregroundStyle(palette.primaryText)
            let meta = [bookmark.bylineNames.map { "By \($0)" }, bookmark.publishedAt.map { NewsDate.short($0) }].compactMap { $0 }
            if !meta.isEmpty {
                Text(meta.joined(separator: " · "))
                    .font(Typography.meta)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
