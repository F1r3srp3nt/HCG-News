import SwiftUI
import NewsCore
import NewsAppModel

struct ArticleScreen: View {
    let id: ArticleID
    @Environment(NewsAppEnvironment.self) private var env
    @State private var model: ArticleModel?

    var body: some View {
        Group {
            if let model { ArticleView(model: model) } else { LoadingStateView() }
        }
        .task(id: id) { if model?.id != id { model = env.articleModel(id: id) } }
    }
}

struct ArticleView: View {
    let model: ArticleModel

    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(ReadingSize.storageKey) private var readingStep = 0
    @AppStorage(LineSpacingChoice.storageKey) private var spacingRaw = LineSpacingChoice.comfortable.rawValue
    @AppStorage(ReadingWidthChoice.storageKey) private var widthRaw = ReadingWidthChoice.standard.rawValue
    @AppStorage(ArticleTypeface.storageKey) private var typefaceRaw = ArticleTypeface.serif.rawValue
    @State private var position: Int?
    @State private var showingReaderSettings = false
    @State private var readAloud = ReadAloudController()
    @State private var resumeOffered = false

    private var width: ReadingWidthChoice { ReadingWidthChoice(rawValue: widthRaw) ?? .standard }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content(proxy: proxy)
                }
                .scrollTargetLayout()
                .padding(.horizontal, sizeClass == .regular ? 40 : 18)
                .padding(.vertical, 20)
                .frame(maxWidth: width.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $position, anchor: .top)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingReaderSettings) { ReaderSettingsSheet() }
        .task {
            if case .idle = model.state { await model.load() }
            if let resume = model.resumeBlockIndex, resume > 2 { resumeOffered = true }
        }
        .refreshable { await model.load() }
        .onDisappear {
            readAloud.stop()
            if let position, position >= 0 { Task { await model.saveReadingPosition(position) } }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(proxy: ScrollViewProxy) -> some View {
        switch model.state {
        case .idle, .loading:
            if let preview = model.preview { ArticleHeader(summary: preview).id(-10) }
            LoadingStateView(label: "Loading article").id(-9)
        case .failed(let error):
            if let preview = model.preview { ArticleHeader(summary: preview).id(-10) }
            failure(error).id(-9)
        case .loaded(let presentation):
            loaded(presentation, proxy: proxy)
        }
    }

    @ViewBuilder
    private func loaded(_ p: ArticlePresentation, proxy: ScrollViewProxy) -> some View {
        let article = p.article
        let s = article.summary
        let typeface = ArticleTypeface(rawValue: typefaceRaw) ?? .serif
        let spacing = (LineSpacingChoice(rawValue: spacingRaw) ?? .comfortable).points

        SourceBanner(source: p.source, updateAvailable: p.downloadUpdateAvailable,
                     canUpdate: model.canDownload) { Task { await model.downloadForOffline() } }
            .id(-8)
        if resumeOffered, let resume = model.resumeBlockIndex {
            Button {
                resumeOffered = false
                withAnimation(nil) { proxy.scrollTo(resume, anchor: .top) }
            } label: {
                Label("Continue where you left off", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.bottom, 12)
            .id(-7)
        }
        ArticleHeader(summary: s).id(-6)
        if s.editorialType == .sponsored || article.sponsor != nil {
            SponsorNoticeView(sponsor: article.sponsor).padding(.top, 16).id(-5)
        }
        if !article.corrections.isEmpty {
            CorrectionsView(corrections: article.corrections).padding(.top, 16).id(-4)
        }
        if !s.disclosures.isEmpty {
            DisclosureBox(disclosures: s.disclosures, authors: s.authors).padding(.top, 16).id(-3)
        }
        if let audio = article.audio {
            ArticleAudioView(audio: audio).padding(.top, 16).id(-2)
        }
        if let image = s.image {
            ArticleFigure(image: image).padding(.top, 20).id(-1)
        }

        Group {
            if article.completeness == .summaryOnly {
                SummaryOnlyNotice(url: s.shareableURL).padding(.top, 20).id(0)
            } else if article.blocks.isEmpty {
                Text("The text of this article couldn't be displayed in the app.")
                    .font(.body).foregroundStyle(Palette.secondaryText).padding(.top, 20).id(0)
            } else {
                ForEach(Array(article.blocks.enumerated()), id: \.offset) { index, block in
                    ContentBlockView(block: block, canonicalURL: s.shareableURL, typeface: typeface, lineSpacing: spacing)
                        .padding(.top, index == 0 ? 24 : 18)
                        .id(index)
                }
            }
            if !article.sources.isEmpty {
                SourcesList(sources: article.sources).padding(.top, 28).id(100_000)
            }
        }
        .dynamicTypeSize(ReadingSize.adjusted(systemTypeSize, step: readingStep))

        if !article.related.isEmpty {
            RelatedStories(items: article.related).padding(.top, 32).id(100_001)
        }
        VStack(alignment: .leading, spacing: 12) {
            RowSeparator()
            if let url = s.shareableURL {
                Link(destination: url) { Label("View on news.hakmicapitalgroup.com", systemImage: "safari") }.font(.footnote)
            }
            PublisherAttribution().padding(.top, 8)
        }
        .padding(.top, 28)
        .id(100_002)
    }

    @ViewBuilder
    private func failure(_ error: UserFacingError) -> some View {
        switch error.kind {
        case .restricted:
            RestrictedArticleNotice(retry: { await model.load() })
        case .notFound where model.isSaved:
            VStack(spacing: 12) {
                MessageStateView(error: error, retry: nil)
                Text("If you downloaded it, the stored copy isn't shown because the publication no longer offers this article.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.center)
                Button("Remove from Saved", role: .destructive) {
                    Task { await env.saved.remove(model.id, alsoDownload: true) }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        default:
            PublicationErrorView(error: error, problems: env.contentConfigurationProblems) { await model.load() }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showingReaderSettings = true } label: { Label("Reading Settings", systemImage: "textformat.size") }
                .keyboardShortcut("t", modifiers: [.command, .shift])

            if model.saveableSummary != nil {
                Button { Task { await model.toggleSaved() } } label: {
                    Label(model.isSaved ? "Remove from Saved" : "Save", systemImage: model.isSaved ? "bookmark.fill" : "bookmark")
                }
                .keyboardShortcut("d", modifiers: .command)
            }

            Menu {
                downloadMenu
                if let article = model.state.value?.article, article.completeness == .full, !article.blocks.isEmpty {
                    Section("On-device voice (not a publication recording)") {
                        Button { readAloud.toggle(article: article) } label: {
                            Label(readAloud.isSpeaking ? "Stop Reading Aloud" : "Read Aloud", systemImage: "speaker.wave.2")
                        }
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }

            if let summary = model.state.value?.article.summary, let url = summary.shareableURL {
                ShareLink(item: url, subject: Text(summary.headline), message: Text(summary.headline)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder
    private var downloadMenu: some View {
        let download = model.download
        if case .downloading? = download?.state {
            Label("Downloading…", systemImage: "arrow.down.circle")
        } else if model.canDownload {
            Button { Task { await model.downloadForOffline() } } label: {
                Label(download?.updateAvailable == true ? "Update Download" : (download?.hasCompleteCopy == true ? "Download Again" : "Download for Offline"),
                      systemImage: "arrow.down.circle")
            }
        } else if let article = model.state.value?.article, !article.isEligibleForOfflineStorage {
            Text(article.summary.access != .public ? "Restricted articles aren't downloaded" : "Only a summary is available")
        }
        if download?.hasCompleteCopy == true {
            Button(role: .destructive) { Task { await model.removeDownload() } } label: {
                Label("Remove Download (Keep Saved)", systemImage: "trash")
            }
        }
    }
}

// MARK: - Pieces

/// Says plainly when the reader is looking at a stored copy rather than the live article.
struct SourceBanner: View {
    let source: ArticleOrigin
    let updateAvailable: Bool
    let canUpdate: Bool
    let update: () -> Void

    var body: some View {
        switch source {
        case .storedCopy(let downloadedAt, let liveError):
            VStack(alignment: .leading, spacing: 4) {
                Label("Stored copy from \(NewsDate.full(downloadedAt))", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline.weight(.semibold))
                Text((liveError?.title ?? "Offline") + ". This is the version saved on this device; the publication may have changed it since.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
            }
            .cardSurface(cornerRadius: 10)
            .padding(.bottom, 16)
        case .live where updateAvailable:
            HStack {
                Label("Your download is older than this version.", systemImage: "arrow.down.circle.dotted")
                    .font(.footnote)
                Spacer()
                if canUpdate { Button("Update Download", action: update).font(.footnote.weight(.semibold)) }
            }
            .cardSurface(cornerRadius: 10)
            .padding(.bottom, 16)
        case .live:
            EmptyView()
        }
    }
}

/// Type, headline, introduction, byline and dates.
struct ArticleHeader: View {
    let summary: ArticleSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KickerLine(editorialType: summary.editorialType, sectionName: summary.section?.name,
                       restricted: summary.access == .restricted)
            Text(summary.headline)
                .font(Typography.headline(.largeTitle, weight: .bold))
                .foregroundStyle(Palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            if let standfirst = summary.standfirst {
                Text(standfirst)
                    .font(Typography.headline(.title3, weight: .regular))
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Rectangle().fill(Palette.separator).frame(width: 60, height: 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(summary.authors) { author in
                    HStack(spacing: 4) {
                        Text("By \(author.name)").font(.subheadline.weight(.semibold))
                        if let title = author.title { Text("· \(title)").font(.subheadline) }
                    }
                    .foregroundStyle(Palette.primaryText)
                }
                if let published = summary.publishedAt {
                    Text("Published \(NewsDate.full(published))").font(Typography.meta).foregroundStyle(Palette.secondaryText)
                } else {
                    Text("Not published").font(Typography.meta).foregroundStyle(Palette.warning)
                }
                if let updated = summary.updatedAt, let published = summary.publishedAt, updated.timeIntervalSince(published) > 60 {
                    Text("Updated \(NewsDate.full(updated))").font(Typography.meta).foregroundStyle(Palette.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct SponsorNoticeView: View {
    let sponsor: SponsorNotice?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sponsored content", systemImage: "megaphone").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.warning)
            if let name = sponsor?.sponsorName {
                Text("Paid for by \(name).").font(.footnote).foregroundStyle(Palette.primaryText)
            }
            if let text = sponsor?.text { Text(text).font(.footnote).foregroundStyle(Palette.secondaryText) }
            if let url = sponsor?.url, LinkPolicy.allowedExternalURL(url) != nil {
                Link("About this sponsor", destination: url).font(.footnote)
            }
            Link("Advertising disclosure", destination: URL(string: "https://news.hakmicapitalgroup.com/advertising-disclosure")!)
                .font(.footnote)
        }
        .cardSurface(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }
}

struct CorrectionsView: View {
    let corrections: [ArticleCorrection]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(corrections.count == 1 ? "Correction" : "Corrections", systemImage: "pencil.and.list.clipboard")
                .font(.subheadline.weight(.semibold))
            ForEach(corrections) { correction in
                VStack(alignment: .leading, spacing: 2) {
                    if let date = correction.issuedAt {
                        Text(NewsDate.full(date)).font(.caption).foregroundStyle(Palette.secondaryText)
                    }
                    Text(correction.text).font(.footnote).foregroundStyle(Palette.primaryText).textSelection(.enabled)
                }
            }
            Link("Corrections policy", destination: URL(string: "https://news.hakmicapitalgroup.com/corrections")!).font(.footnote)
        }
        .cardSurface(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }
}

/// Disclosures attached by the publication to the article's verified authors,
/// shown verbatim. The app never writes or infers a disclosure.
struct DisclosureBox: View {
    let disclosures: [AuthorDisclosure]
    let authors: [Author]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Author disclosure", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.primaryText)
            ForEach(disclosures) { disclosure in
                VStack(alignment: .leading, spacing: 2) {
                    if authors.count > 1, let name = authors.first(where: { $0.id == disclosure.authorID })?.name {
                        Text(name).font(.footnote.weight(.semibold)).foregroundStyle(Palette.primaryText)
                    }
                    Text(disclosure.text)
                        .font(.footnote)
                        .foregroundStyle(Palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .cardSurface(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }
}

struct SummaryOnlyNotice: View {
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Only a summary is available in the app for this article.")
                .font(.body).foregroundStyle(Palette.primaryText)
            if let url {
                Link(destination: url) { Label("Read the full article on the web", systemImage: "safari") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

struct SourcesList: View {
    let sources: [ArticleSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sources").font(Typography.headline(.title3)).foregroundStyle(Palette.primaryText).accessibilityAddTraits(.isHeader)
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 2) {
                    if let url = source.url {
                        Link(destination: url) { Text(source.title).underline().multilineTextAlignment(.leading) }
                            .accessibilityHint("Opens \(url.host ?? "the source") in Safari")
                    } else {
                        Text(source.title).foregroundStyle(Palette.primaryText)
                    }
                    if let publisher = source.publisher {
                        Text(publisher).font(.footnote).foregroundStyle(Palette.secondaryText)
                    }
                }
            }
        }
    }
}

/// Related stories supplied by the publication's metadata (never computed in the app).
struct RelatedStories: View {
    let items: [ArticleSummary]
    @Environment(NewsAppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedHeader(title: "Related")
            ForEach(items) { item in
                NavigationLink(value: Route.article(item.id)) {
                    ArticleRow(summary: item, showsStandfirst: false, download: env.saved.download(for: item.id))
                }
                .buttonStyle(.plain)
                RowSeparator()
            }
        }
    }
}

/// Shown when the publication marks an article as restricted.
struct RestrictedArticleNotice: View {
    let retry: () async -> Void
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(Router.self) private var router

    var body: some View {
        switch env.account.status?.authentication {
        case .signedIn?:
            MessageStateView(title: "No access",
                             message: "The publication marks this article as restricted, and HCG did not grant your account access to it. Access is managed centrally by HCG.",
                             systemImage: "lock.slash", retry: retry)
        case .unavailable?, nil:
            MessageStateView(title: "Sign-in required",
                             message: "The publication marks this article as available to authorised HCG accounts only. HCG Connect sign-in isn't set up in this app yet.",
                             systemImage: "lock")
        default:
            MessageStateView(title: "Sign-in required",
                             message: "The publication marks this article as available to authorised HCG accounts only.",
                             systemImage: "lock", retry: nil,
                             action: ("Sign In with HCG Connect", { router.showSettings(.account) }))
        }
    }
}

/// Reading controls: text size, line spacing, width and typeface.
struct ReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ReadingSize.storageKey) private var readingStep = 0
    @AppStorage(LineSpacingChoice.storageKey) private var spacingRaw = LineSpacingChoice.comfortable.rawValue
    @AppStorage(ReadingWidthChoice.storageKey) private var widthRaw = ReadingWidthChoice.standard.rawValue
    @AppStorage(ArticleTypeface.storageKey) private var typefaceRaw = ArticleTypeface.serif.rawValue
    @AppStorage(AppearanceChoice.storageKey) private var appearanceRaw = AppearanceChoice.system.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $readingStep, in: ReadingSize.range) {
                        Text("Text size: \(ReadingSize.label(for: readingStep))")
                    }
                    Picker("Line spacing", selection: $spacingRaw) {
                        ForEach(LineSpacingChoice.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Reading width", selection: $widthRaw) {
                        ForEach(ReadingWidthChoice.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Typeface", selection: $typefaceRaw) {
                        ForEach(ArticleTypeface.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } footer: {
                    Text("Text size starts from your device's text size, including accessibility sizes. Reading width applies on larger screens.")
                }
                Section {
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
