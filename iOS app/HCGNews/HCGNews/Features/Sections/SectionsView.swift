import SwiftUI
import NewsCore
import NewsAppModel

/// Sections exactly as the publication's backend defines them (including any
/// hierarchy such as Politics → Norwegian Politics / International Politics).
struct SectionsView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.palette) private var palette

    var body: some View {
        let model = env.sections
        Group {
            switch model.state {
            case .idle, .loading:
                LoadingStateView(label: "Loading sections")
            case .failed(let error) where error.kind == .notConfigured:
                ScrollView { NotConnectedView(problems: env.contentConfigurationProblems) }
            case .failed(let error):
                ScrollView { MessageStateView(error: error, retry: { await model.reload() }) }
            case .loaded(let nodes) where nodes.isEmpty:
                ScrollView {
                    MessageStateView(title: "No sections",
                                     message: "The publication doesn't list any sections right now.",
                                     systemImage: "list.bullet.rectangle",
                                     retry: { await model.reload() })
                }
            case .loaded(let nodes):
                List {
                    ForEach(nodes) { node in
                        NavigationLink(value: Route.section(slug: node.section.slug, name: node.section.name)) {
                            SectionRowLabel(section: node.section, isChild: false)
                        }
                        ForEach(node.children) { child in
                            NavigationLink(value: Route.section(slug: child.slug, name: child.name)) {
                                SectionRowLabel(section: child, isChild: true)
                            }
                            .accessibilityLabel("\(child.name), in \(node.section.name)")
                        }
                    }
                    .listRowBackground(palette.surface)
                }
                .refreshable { await model.reload() }
            }
        }
        .screenBackground()
        .navigationTitle("Sections")
        .task { await model.loadIfNeeded() }
    }
}

struct SectionRowLabel: View {
    let section: NewsSection
    let isChild: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.name)
                .font(isChild ? .body : Typography.headline(.headline))
                .foregroundStyle(palette.primaryText)
            if let description = section.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.leading, isChild ? 16 : 0)
        .padding(.vertical, 4)
    }
}

/// Articles in one section, with pagination.
struct SectionFeedView: View {
    let slug: String
    let name: String

    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let model = env.feed(forSection: slug)
        ScrollView {
            Group {
                switch model.state {
                case .idle, .loading:
                    LoadingStateView()
                case .failed(let error) where error.kind == .notConfigured:
                    NotConnectedView(problems: env.contentConfigurationProblems)
                case .failed(let error):
                    MessageStateView(error: error, retry: { await model.reload() })
                case .loaded(let items) where items.isEmpty:
                    MessageStateView(title: "Nothing in \(name) yet",
                                     message: "There are no published articles in this section right now.",
                                     systemImage: "tray",
                                     retry: { await model.reload() })
                case .loaded(let items):
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let error = model.loadMoreError {
                            InlineErrorRow(error: error) { await model.loadMore() }
                                .padding(.top, 12)
                        }
                        ForEach(items) { item in
                            NavigationLink(value: Route.article(item.id)) {
                                ArticleRow(summary: item)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if item.id == items.last?.id { Task { await model.loadMore() } }
                            }
                            Rectangle().fill(palette.separator).frame(height: 1)
                        }
                        if model.isLoadingMore {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        }
                    }
                }
            }
            .padding(.horizontal, sizeClass == .regular ? 32 : 16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.reload() }
        .screenBackground()
        .navigationTitle(name)
        .task { await model.loadIfNeeded() }
    }
}
