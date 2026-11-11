import SwiftUI
import NewsCore
import NewsAppModel

enum OfflineLimit {
    static let storageKey = "offlineLimitMB"
    static let choices = [100, 250, 500, 1000, 2000]
}

/// Saved articles on this device, with offline downloads.
struct SavedView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @AppStorage(OfflineLimit.storageKey) private var limitMB = 500
    @State private var confirmClear = false

    var body: some View {
        let saved = env.saved
        List {
            notices(saved)
            if saved.bookmarks.isEmpty {
                Section {
                    MessageStateView(title: "No saved articles",
                                     message: "Tap Save while reading to keep an article here. Download it to read without a connection.",
                                     systemImage: "bookmark")
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(saved.bookmarks) { bookmark in
                        NavigationLink(value: Route.article(bookmark.articleID)) {
                            SavedRow(bookmark: bookmark, download: saved.download(for: bookmark.articleID))
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Remove", role: .destructive) { Task { await saved.remove(bookmark.articleID, alsoDownload: true) } }
                            if saved.download(for: bookmark.articleID)?.hasCompleteCopy == true {
                                Button("Remove Download") { Task { await saved.removeDownload(bookmark.articleID) } }
                                    .tint(Palette.silver)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if saved.canDownload {
                                Button(downloadTitle(saved.download(for: bookmark.articleID))) {
                                    Task { await saved.downloadArticle(bookmark.summary) }
                                }
                                .tint(Palette.accent)
                            }
                        }
                        .contextMenu { contextMenu(bookmark, saved: saved) }
                        .listRowBackground(Palette.elevated)
                    }
                } header: {
                    Text("\(saved.bookmarks.count) saved")
                }
            }
            storage(saved)
        }
        .screenBackground()
        .navigationTitle("Saved")
        .task {
            saved.limitBytes = Int64(limitMB) * 1024 * 1024
            await saved.load()
        }
        .onChange(of: limitMB) { _, value in saved.limitBytes = Int64(value) * 1024 * 1024 }
        .confirmationDialog("Remove all downloaded articles?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Remove Downloads", role: .destructive) { Task { await saved.clearAllDownloads() } }
        } message: {
            Text("Saved articles stay in your list. Only the offline copies are removed.")
        }
    }

    @ViewBuilder
    private func notices(_ saved: SavedModel) -> some View {
        let interrupted = saved.interruptedIDs
        if !interrupted.isEmpty || saved.lastError != nil || saved.recoveredFromCorruption || saved.migratedFromVersion != nil || saved.newerFileVersion != nil {
            Section {
                if !interrupted.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(interrupted.count) download\(interrupted.count == 1 ? " was" : "s were") interrupted", systemImage: "exclamationmark.arrow.circlepath")
                            .font(.subheadline.weight(.semibold))
                        if saved.canDownload {
                            Button("Resume Downloads") { Task { await saved.resumeInterrupted() } }
                                .buttonStyle(SecondaryButtonStyle())
                        } else {
                            Text("Connect the publication to resume them.").font(.footnote).foregroundStyle(Palette.secondaryText)
                        }
                    }
                }
                if let error = saved.lastError {
                    Text(error).font(.footnote).foregroundStyle(Palette.warning)
                }
                if saved.recoveredFromCorruption {
                    Text("Your saved list couldn't be read and was set aside safely. New saves will appear here.")
                        .font(.footnote).foregroundStyle(Palette.secondaryText)
                }
                if saved.migratedFromVersion != nil {
                    Text("Your saved articles were updated to the new storage format. A backup of the old list was kept.")
                        .font(.footnote).foregroundStyle(Palette.secondaryText)
                }
                if saved.newerFileVersion != nil {
                    Text("Saved articles were last changed by a newer version of HCG News. They're shown read-only here.")
                        .font(.footnote).foregroundStyle(Palette.warning)
                }
            }
            .listRowBackground(Palette.surface)
        }
    }

    @ViewBuilder
    private func storage(_ saved: SavedModel) -> some View {
        Section {
            LabeledContent("Offline storage used", value: ByteSize.string(saved.usageBytes))
            Picker("Download limit", selection: $limitMB) {
                ForEach(OfflineLimit.choices, id: \.self) { mb in Text(ByteSize.string(Int64(mb) * 1024 * 1024)).tag(mb) }
            }
            Button("Remove All Downloads", role: .destructive) { confirmClear = true }
                .disabled(saved.usageBytes == 0)
        } header: {
            Text("Offline")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloads keep the article text and its images on this device, so you can read them in airplane mode. Restricted articles aren't stored offline.")
                if case .unavailable(let reason) = SecondaryFeatures.savedArticleSync { Text(reason) }
            }
        }
        .listRowBackground(Palette.elevated)
    }

    @ViewBuilder
    private func contextMenu(_ bookmark: Bookmark, saved: SavedModel) -> some View {
        let download = saved.download(for: bookmark.articleID)
        if saved.canDownload {
            Button { Task { await saved.downloadArticle(bookmark.summary) } } label: {
                Label(downloadTitle(download), systemImage: "arrow.down.circle")
            }
        }
        if download?.hasCompleteCopy == true {
            Button { Task { await saved.removeDownload(bookmark.articleID) } } label: {
                Label("Remove Download (Keep Saved)", systemImage: "arrow.down.circle.dotted")
            }
        }
        if let url = bookmark.canonicalURL {
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        Button(role: .destructive) { Task { await saved.remove(bookmark.articleID, alsoDownload: true) } } label: {
            Label("Remove from Saved", systemImage: "trash")
        }
    }

    private func downloadTitle(_ entry: OfflineEntry?) -> String {
        guard let entry else { return "Download" }
        if entry.updateAvailable { return "Update Download" }
        switch entry.state {
        case .failed, .interrupted: return "Retry Download"
        default: return entry.hasCompleteCopy ? "Download Again" : "Download"
        }
    }
}

struct SavedRow: View {
    let bookmark: Bookmark
    let download: OfflineEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let type = bookmark.editorialType { EditorialLabel(type: type) }
                if let section = bookmark.sectionName {
                    Text(section).font(Typography.kicker).foregroundStyle(Palette.secondaryText)
                }
            }
            Text(bookmark.headline)
                .font(Typography.headline(.headline))
                .foregroundStyle(Palette.primaryText)
            let meta = [bookmark.bylineNames.map { "By \($0)" }, bookmark.publishedAt.map { NewsDate.short($0) }].compactMap { $0 }
            if !meta.isEmpty {
                Text(meta.joined(separator: " · ")).font(Typography.meta).foregroundStyle(Palette.secondaryText)
            }
            DownloadStatusLine(entry: download)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Download state in words, never colour alone.
struct DownloadStatusLine: View {
    let entry: OfflineEntry?

    var body: some View {
        if let entry {
            HStack(spacing: 6) {
                switch entry.state {
                case .downloading:
                    ProgressView().controlSize(.mini)
                    Text("Downloading…")
                case .downloaded:
                    Image(systemName: entry.updateAvailable ? "arrow.down.circle.dotted" : "arrow.down.circle.fill")
                        .foregroundStyle(Palette.accent)
                    Text(downloadedText(entry))
                case .failed(let reason):
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.warning)
                    Text(entry.hasCompleteCopy ? "Update failed: \(reason) Your earlier copy is kept." : "Download failed: \(reason)")
                case .interrupted:
                    Image(systemName: "pause.circle").foregroundStyle(Palette.warning)
                    Text("Download interrupted")
                }
            }
            .font(.caption)
            .foregroundStyle(Palette.secondaryText)
        } else {
            Text("Not downloaded · needs a connection to read")
                .font(.caption)
                .foregroundStyle(Palette.silver)
        }
    }

    private func downloadedText(_ entry: OfflineEntry) -> String {
        var text = "Downloaded"
        if let date = entry.downloadedAt { text += " \(NewsDate.short(date))" }
        text += " · \(ByteSize.string(entry.bytes))"
        if entry.missingImages > 0 { text += " · \(entry.missingImages) image\(entry.missingImages == 1 ? "" : "s") unavailable offline" }
        if entry.updateAvailable { text += " · update available" }
        return text
    }
}
