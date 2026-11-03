import SwiftUI
import NewsCore
import NewsAppModel

struct HomeView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.palette) private var palette

    var body: some View {
        let home = env.home
        ScrollView {
            content(home: home)
                .padding(.horizontal, sizeClass == .regular ? 32 : 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
        }
        .refreshable { await home.reload() }
        .screenBackground()
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { MastheadTitle() }
        }
        .task { await home.loadIfNeeded() }
    }

    @ViewBuilder
    private func content(home: HomeModel) -> some View {
        switch home.state {
        case .idle, .loading:
            LoadingStateView(label: "Loading HCG News")
        case .failed(let error) where error.kind == .notConfigured:
            NotConnectedView(problems: env.contentConfigurationProblems)
        case .failed(let error):
            MessageStateView(error: error, retry: { await home.reload() })
        case .loaded(let content):
            loaded(content, home: home)
        }
    }

    @ViewBuilder
    private func loaded(_ content: HomeContent, home: HomeModel) -> some View {
        @Bindable var home = home
        let wide = sizeClass == .regular
        LazyVStack(alignment: .leading, spacing: 0) {
            if let error = home.loadMoreError {
                InlineErrorRow(error: error) { await home.reload() }
                    .padding(.top, 12)
            }
            if home.breaking.current != nil {
                BreakingNewsBanner(carousel: $home.breaking) { article in
                    router.open(.article(article.id), compact: sizeClass == .compact)
                }
                .padding(.top, 12)
            }

            if content.featured.isEmpty && content.latest.isEmpty {
                MessageStateView(title: "No articles yet",
                                 message: "The publication has no published articles to show right now.",
                                 systemImage: "newspaper",
                                 retry: { await home.reload() })
            }

            if let lead = content.featured.first {
                FeedHeader(title: "Featured")
                NavigationLink(value: Route.article(lead.id)) {
                    LeadArticleCard(summary: lead, wide: wide)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                ForEach(content.featured.dropFirst()) { item in
                    row(item)
                }
            }

            if !content.latest.isEmpty {
                FeedHeader(title: "Latest")
                ForEach(content.latest) { item in
                    row(item)
                        .onAppear {
                            if item.id == content.latest.last?.id {
                                Task { await home.loadMore() }
                            }
                        }
                }
                if home.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if content.nextCursor == nil, content.latest.count > 5 {
                    Text("You're up to date.")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            }
        }
        .frame(maxWidth: wide ? 1000 : 760, alignment: .leading)
    }

    private func row(_ item: ArticleSummary) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: Route.article(item.id)) {
                ArticleRow(summary: item)
            }
            .buttonStyle(.plain)
            Rectangle().fill(palette.separator).frame(height: 1)
        }
    }
}
