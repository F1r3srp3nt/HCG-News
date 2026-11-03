import SwiftUI
import NewsCore
import NewsAppModel

struct ArticleScreen: View {
    let id: ArticleID
    @Environment(NewsAppEnvironment.self) private var env
    @State private var model: ArticleModel?

    var body: some View {
        Group {
            if let model {
                ArticleView(model: model)
            } else {
                LoadingStateView()
            }
        }
        .task(id: id) {
            if model?.id != id { model = env.articleModel(id: id) }
        }
    }
}

struct ArticleView: View {
    let model: ArticleModel

    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(ReadingSize.storageKey) private var readingStep = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch model.state {
                case .idle, .loading:
                    if let preview = model.preview {
                        ArticleHeader(summary: preview)
                    }
                    LoadingStateView(label: "Loading article")
                case .failed(let error):
                    if let preview = model.preview {
                        ArticleHeader(summary: preview)
                    }
                    failure(error)
                case .loaded(let article):
                    loaded(article)
                }
            }
            .padding(.horizontal, sizeClass == .regular ? 40 : 18)
            .padding(.vertical, 20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .safeLinkHandling()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task {
            if case .idle = model.state { await model.load() }
        }
        .refreshable { await model.load() }
    }

    // MARK: Content

    @ViewBuilder
    private func loaded(_ article: Article) -> some View {
        let s = article.summary
        ArticleHeader(summary: s)
        if !s.disclosures.isEmpty {
            DisclosureBox(disclosures: s.disclosures, authors: s.authors)
                .padding(.top, 16)
        }
        if let image = s.image {
            ArticleFigure(image: image)
                .padding(.top, 20)
        }
        Group {
            if article.blocks.isEmpty {
                Text("The text of this article couldn't be displayed in the app.")
                    .font(.body)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.top, 20)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                        ContentBlockView(block: block, canonicalURL: s.shareableURL)
                    }
                }
                .padding(.top, 24)
            }
            if !article.sources.isEmpty {
                SourcesList(sources: article.sources)
                    .padding(.top, 28)
            }
        }
        .dynamicTypeSize(ReadingSize.adjusted(systemTypeSize, step: readingStep))

        if let url = s.shareableURL {
            Divider().padding(.top, 28)
            Link(destination: url) {
                Label("View on news.hakmicapitalgroup.com", systemImage: "safari")
                    .font(.footnote)
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func failure(_ error: UserFacingError) -> some View {
        switch error.kind {
        case .restricted:
            RestrictedArticleNotice(retry: { await model.load() })
        case .notConfigured:
            NotConnectedView(problems: env.contentConfigurationProblems)
        case .notFound where model.isSaved:
            VStack(spacing: 12) {
                MessageStateView(error: error, retry: nil)
                Button("Remove from Saved", role: .destructive) {
                    Task { await model.toggleSaved() }
                }
            }
        default:
            MessageStateView(error: error, retry: { await model.load() })
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Text Size", selection: $readingStep) {
                    ForEach(Array(ReadingSize.range), id: \.self) { step in
                        Text(ReadingSize.label(for: step)).tag(step)
                    }
                }
            } label: {
                Label("Text Size", systemImage: "textformat.size")
            }

            if model.saveableSummary != nil {
                Button {
                    Task { await model.toggleSaved() }
                } label: {
                    Label(model.isSaved ? "Remove from Saved" : "Save",
                          systemImage: model.isSaved ? "bookmark.fill" : "bookmark")
                }
            }

            if let summary = model.state.value?.summary, let url = summary.shareableURL {
                ShareLink(item: url, subject: Text(summary.headline), message: Text(summary.headline)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

/// Type, headline, standfirst, byline, dates.
struct ArticleHeader: View {
    let summary: ArticleSummary
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KickerLine(editorialType: summary.editorialType, sectionName: summary.section?.name,
                       restricted: summary.access == .restricted)
            Text(summary.headline)
                .font(Typography.headline(.largeTitle, weight: .bold))
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            if let standfirst = summary.standfirst {
                Text(standfirst)
                    .font(Typography.headline(.title3, weight: .regular))
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if !summary.authors.isEmpty {
                    ForEach(summary.authors) { author in
                        HStack(spacing: 4) {
                            Text("By \(author.name)").font(.subheadline.weight(.semibold))
                            if let title = author.title {
                                Text("· \(title)").font(.subheadline)
                            }
                        }
                        .foregroundStyle(palette.primaryText)
                    }
                }
                if let published = summary.publishedAt {
                    Text("Published \(NewsDate.full(published))")
                        .font(Typography.meta)
                        .foregroundStyle(palette.secondaryText)
                }
                if let updated = summary.updatedAt, let published = summary.publishedAt,
                   updated.timeIntervalSince(published) > 60 {
                    Text("Updated \(NewsDate.full(updated))")
                        .font(Typography.meta)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Disclosures attached by the backend to the article's verified authors.
/// The text is shown exactly as supplied; the app never writes or infers one.
struct DisclosureBox: View {
    let disclosures: [AuthorDisclosure]
    let authors: [Author]
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Disclosure", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.primaryText)
            ForEach(disclosures) { disclosure in
                VStack(alignment: .leading, spacing: 2) {
                    if authors.count > 1, let name = authors.first(where: { $0.id == disclosure.authorID })?.name {
                        Text(name).font(.footnote.weight(.semibold)).foregroundStyle(palette.primaryText)
                    }
                    Text(disclosure.text)
                        .font(.footnote)
                        .foregroundStyle(palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.accent).frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
        }
        .accessibilityElement(children: .combine)
    }
}

struct SourcesList: View {
    let sources: [ArticleSource]
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sources")
                .font(Typography.headline(.title3))
                .foregroundStyle(palette.primaryText)
                .accessibilityAddTraits(.isHeader)
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 2) {
                    if let url = source.url {
                        Link(destination: url) {
                            Text(source.title).underline()
                                .multilineTextAlignment(.leading)
                        }
                        .accessibilityHint("Opens \(url.host ?? "the source") in Safari")
                    } else {
                        Text(source.title).foregroundStyle(palette.primaryText)
                    }
                    if let publisher = source.publisher {
                        Text(publisher).font(.footnote).foregroundStyle(palette.secondaryText)
                    }
                }
            }
        }
    }
}

/// Shown when the backend explicitly marks an article as restricted.
struct RestrictedArticleNotice: View {
    let retry: () async -> Void
    @Environment(NewsAppEnvironment.self) private var env

    var body: some View {
        let auth = env.account.status?.authentication
        switch auth {
        case .signedIn?:
            MessageStateView(
                title: "No access",
                message: "HCG News marks this article as restricted, and HCG did not grant your account access to it. Access is managed centrally by HCG.",
                systemImage: "lock.slash", retry: retry)
        case .unavailable?, nil:
            MessageStateView(
                title: "Sign-in required",
                message: "HCG News marks this article as available to authorised HCG accounts only. Signing in with HCG Connect isn't available in this version yet.",
                systemImage: "lock")
        default:
            VStack(spacing: 12) {
                MessageStateView(
                    title: "Sign-in required",
                    message: "HCG News marks this article as available to authorised HCG accounts only.",
                    systemImage: "lock")
                Button("Sign In with HCG Connect") {
                    Task {
                        await env.account.signIn()
                        await retry()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
