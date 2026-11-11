import SwiftUI
import NewsCore
import NewsAppModel

struct SearchView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var query = ""

    var body: some View {
        let model = env.search
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch model.state {
                case .idle:
                    hint
                case .loading:
                    LoadingStateView(label: "Searching")
                case .failed(let error) where error.kind == .notConfigured:
                    NotConnectedView(problems: env.contentConfigurationProblems)
                case .failed(let error):
                    MessageStateView(error: error, retry: { await model.search(query) })
                case .loaded(let results):
                    if results.scope == .loadedArticlesOnly {
                        ScopeNotice(loadedCount: env.index.count)
                            .padding(.top, 12)
                    }
                    if results.items.isEmpty {
                        MessageStateView(title: "No results",
                                         message: "Nothing matched “\(results.query)”.",
                                         systemImage: "magnifyingglass")
                    } else {
                        ForEach(results.items) { item in
                            NavigationLink(value: Route.article(item.id)) {
                                ArticleRow(summary: item, showsStandfirst: false)
                            }
                            .buttonStyle(.plain)
                            Rectangle().fill(palette.separator).frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, sizeClass == .regular ? 32 : 16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search HCG News")
        .task(id: query) {
            // Debounce typing; cancelled automatically when the query changes.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
        .task { _ = await model.resolveScope() }
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 8) {
            if env.search.scope == .loadedArticlesOnly {
                ScopeNotice(loadedCount: env.index.count)
            }
            Text("Search headlines, summaries, sections and authors.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.top, 16)
    }
}

/// States plainly that search is limited when the backend offers no search.
struct ScopeNotice: View {
    let loadedCount: Int
    @Environment(\.palette) private var palette

    var body: some View {
        Label {
            Text("Search covers only the \(loadedCount) article\(loadedCount == 1 ? "" : "s") loaded on this device during this session, not the full publication archive.")
                .font(.footnote)
                .foregroundStyle(palette.primaryText)
        } icon: {
            Image(systemName: "info.circle").foregroundStyle(palette.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
