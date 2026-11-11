import SwiftUI
import NewsCore
import NewsAppModel

struct SearchView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var query = ""
    @State private var showingFilters = false
    @State private var searchPresented = false

    var body: some View {
        let model = env.search
        @Bindable var bindable = model
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.availableScopes.count > 1 {
                    Picker("Search in", selection: $bindable.scope) {
                        ForEach(model.availableScopes) { scope in Text(scope.title).tag(scope) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Search scope")
                }
                ScopeNotice(text: model.scope.explanation, count: model.scope == .loadedArticles ? env.index.count : nil)
                if !model.filters.isEmpty || showingFilters {
                    SearchFilterBar(filters: $bindable.filters, sections: env.sections.allSections,
                                    serverKinds: model.serverFilterKinds, scope: model.scope)
                }
                results(model)
            }
            .padding(.horizontal, sizeClass == .regular ? 32 : 16)
            .padding(.top, 8)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Search")
        .searchable(text: $query, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search HCG News")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingFilters.toggle() } label: {
                    Label("Filters", systemImage: model.filters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task(id: SearchKey(query: query, scope: model.scope, filters: model.filters)) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
        .task {
            await model.resolveScopes()
            await env.sections.loadIfNeeded()
        }
        .onChange(of: router.searchFocusRequest) { _, _ in searchPresented = true }
    }

    struct SearchKey: Equatable {
        let query: String
        let scope: SearchScope
        let filters: SearchFilters
    }

    @ViewBuilder
    private func results(_ model: SearchModel) -> some View {
        switch model.state {
        case .idle:
            Text("Search headlines, summaries, sections and authors.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
                .padding(.top, 8)
        case .loading:
            LoadingStateView(label: "Searching")
        case .failed(let error):
            PublicationErrorView(error: error, problems: env.contentConfigurationProblems) { await model.search(query) }
        case .loaded(let results):
            if !results.locallyAppliedFilters.isEmpty {
                Label("The publication's search doesn't support the \(results.locallyAppliedFilters.map(\.rawValue).sorted().joined(separator: " and ")) filter, so it only narrows the results returned.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
            }
            if results.items.isEmpty {
                MessageStateView(title: "No results", message: "Nothing matched “\(results.query)” in \(results.scope.title.lowercased()).",
                                 systemImage: "magnifyingglass")
            } else {
                Text("\(results.items.count) result\(results.items.count == 1 ? "" : "s")")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
                LazyVStack(spacing: 0) {
                    ForEach(results.items) { item in
                        NavigationLink(value: Route.article(item.id)) {
                            ArticleRow(summary: item, showsStandfirst: false, download: env.saved.download(for: item.id))
                        }
                        .buttonStyle(.plain)
                        .onAppear { if item.id == results.items.last?.id { Task { await model.loadMore() } } }
                        RowSeparator()
                    }
                }
            }
        }
    }
}

/// Plain statement of what the search covers.
struct ScopeNotice: View {
    let text: String
    let count: Int?

    var body: some View {
        Label {
            Text(count.map { "\(text) (\($0) loaded)" } ?? text)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryText)
        } icon: {
            Image(systemName: "info.circle").foregroundStyle(Palette.silver)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SearchFilterBar: View {
    @Binding var filters: SearchFilters
    let sections: [NewsSection]
    let serverKinds: Set<SearchFilterKind>
    let scope: SearchScope

    private let types: [EditorialType] = [.news, .analysis, .opinion, .sponsored, .announcement]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    Button("Any type") { filters.editorialType = nil }
                    ForEach(types, id: \.self) { type in Button(type.label) { filters.editorialType = type } }
                } label: {
                    filterLabel(title: filters.editorialType?.label ?? "Any type", kind: .type)
                }
                Menu {
                    Button("Any section") { filters.sectionSlug = nil }
                    ForEach(sections) { section in Button(section.name) { filters.sectionSlug = section.slug } }
                } label: {
                    filterLabel(title: sections.first { $0.slug == filters.sectionSlug }?.name ?? "Any section", kind: .section)
                }
                .disabled(sections.isEmpty)
                if !filters.isEmpty {
                    Button("Clear") { filters = SearchFilters() }.font(.footnote.weight(.semibold))
                }
            }
        }
    }

    private func filterLabel(title: String, kind: SearchFilterKind) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if scope == .publication, !serverKinds.contains(kind) {
                Image(systemName: "iphone").accessibilityLabel("applied on this device")
            }
            Image(systemName: "chevron.down").font(.caption2)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: 1))
    }
}
