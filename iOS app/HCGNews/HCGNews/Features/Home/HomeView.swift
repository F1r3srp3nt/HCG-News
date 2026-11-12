import SwiftUI
import NewsCore
import NewsAppModel

struct HomeView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let home = env.home
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Masthead()
                    content(home: home)
                        .padding(.horizontal, sizeClass == .regular ? 32 : 16)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 1040)
                        .frame(maxWidth: .infinity)
                }
            }
            .refreshable { await home.reload() }
            .onAppear {
                // Restore the reader's place when returning from an article or after a layout change.
                if let anchor = home.scrollAnchor { proxy.scrollTo(anchor, anchor: .center) }
            }
        }
        .screenBackground()
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) { CompactMasthead() }
        }
        .task {
            await home.loadIfNeeded()
            await env.sections.loadIfNeeded()
        }
    }

    @ViewBuilder
    private func content(home: HomeModel) -> some View {
        switch home.state {
        case .idle, .loading:
            LoadingStateView(label: "Loading HCG News")
        case .failed(let error):
            PublicationErrorView(error: error, problems: env.contentConfigurationProblems) { await home.reload() }
        case .loaded(let content):
            loaded(content, home: home)
        }
    }

    @ViewBuilder
    private func loaded(_ content: HomeContent, home: HomeModel) -> some View {
        @Bindable var home = home
        let wide = sizeClass == .regular
        LazyVStack(alignment: .leading, spacing: 0) {
            if let error = home.refreshError {
                InlineErrorRow(error: error) { await home.reload() }.padding(.top, 12)
            }
            if home.breaking.current != nil {
                BreakingNewsBanner(carousel: $home.breaking) { article in
                    home.scrollAnchor = article.id
                    router.open(.article(article.id))
                }
                .padding(.top, 14)
            }
            SectionStrip()

            if content.isEmpty {
                MessageStateView(title: "No articles yet",
                                 message: env.platformAccount != nil
                                    ? "The publication returned no published articles. If articles are live on news.hakmicapitalgroup.com, the publication hasn't opened public reading to apps yet; Settings › Advanced › Check Connection shows the details."
                                    : "The publication has no published articles to show right now.",
                                 systemImage: "newspaper", retry: { await home.reload() })
            }

            if let lead = content.lead {
                FeedHeader(title: content.hasEditorialFeatured ? "Featured" : "Top story")
                link(lead, home: home) {
                    LeadArticleCard(summary: lead, wide: wide, download: env.saved.download(for: lead.id))
                        .padding(.vertical, 16)
                }
                RowSeparator()
                // Further editorially featured stories (only when the publication marked them).
                ForEach(content.featured.dropFirst()) { item in row(item, home: home) }
            }

            let latest = content.hasEditorialFeatured ? content.latest : Array(content.latest.dropFirst())
            if !latest.isEmpty {
                FeedHeader(title: "Latest", trailing: home.lastUpdated.map { "Updated \(NewsDate.short($0))" })
                ForEach(latest) { item in
                    row(item, home: home)
                        .onAppear {
                            if item.id == latest.last?.id { Task { await home.loadMore() } }
                        }
                }
                if home.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if content.nextCursor == nil, latest.count > 6 {
                    Text("You're up to date.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            }
        }
        .frame(maxWidth: wide ? 1040 : 760, alignment: .leading)
    }

    private func link<Label: View>(_ item: ArticleSummary, home: HomeModel, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink(value: Route.article(item.id)) { label() }
            .buttonStyle(.plain)
            .id(item.id)
            .simultaneousGesture(TapGesture().onEnded { home.scrollAnchor = item.id })
    }

    private func row(_ item: ArticleSummary, home: HomeModel) -> some View {
        VStack(spacing: 0) {
            link(item, home: home) { ArticleRow(summary: item, download: env.saved.download(for: item.id)) }
            RowSeparator()
        }
    }
}

/// Horizontal section navigation from the content service's own sections.
struct SectionStrip: View {
    @Environment(NewsAppEnvironment.self) private var env

    var body: some View {
        if case .loaded(let nodes) = env.sections.state, !nodes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(nodes) { node in
                        NavigationLink(value: Route.section(slug: node.section.slug, name: node.section.name)) {
                            Text(node.section.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.primaryText)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 12)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sections")
        }
    }
}
