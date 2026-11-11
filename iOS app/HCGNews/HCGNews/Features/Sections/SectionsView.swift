import SwiftUI
import NewsCore
import NewsAppModel

/// Sections exactly as the content service defines them, including hierarchy.
/// Sections with an unknown parent are kept, never dropped.
struct SectionsView: View {
    @Environment(NewsAppEnvironment.self) private var env

    var body: some View {
        let model = env.sections
        Group {
            switch model.state {
            case .idle, .loading:
                LoadingStateView(label: "Loading sections")
            case .failed(let error):
                ScrollView { PublicationErrorView(error: error, problems: env.contentConfigurationProblems) { await model.reload() } }
            case .loaded(let nodes) where nodes.isEmpty:
                ScrollView {
                    MessageStateView(title: "No sections", message: "The publication doesn't list any sections right now.",
                                     systemImage: "square.grid.2x2", retry: { await model.reload() })
                }
            case .loaded(let nodes):
                List {
                    ForEach(nodes) { node in
                        Section {
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
                    }
                    .listRowBackground(Palette.elevated)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.name)
                .font(isChild ? .body : Typography.headline(.headline))
                .foregroundStyle(Palette.primaryText)
            if let description = section.description, !description.isEmpty {
                Text(description).font(.footnote).foregroundStyle(Palette.secondaryText).lineLimit(2)
            }
        }
        .padding(.leading, isChild ? 16 : 0)
        .padding(.vertical, 4)
    }
}

/// Articles in one section, with pagination and scroll restoration.
struct SectionFeedView: View {
    let slug: String
    let name: String

    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let model = env.feed(forSection: slug)
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    switch model.state {
                    case .idle, .loading:
                        LoadingStateView()
                    case .failed(let error):
                        PublicationErrorView(error: error, problems: env.contentConfigurationProblems) { await model.reload() }
                    case .loaded(let items) where items.isEmpty:
                        MessageStateView(title: "Nothing in \(name) yet",
                                         message: "There are no published articles in this section right now.",
                                         systemImage: "tray", retry: { await model.reload() })
                    case .loaded(let items):
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if let error = model.refreshError {
                                InlineErrorRow(error: error) { await model.loadMore() }.padding(.top, 12)
                            }
                            ForEach(items) { item in
                                NavigationLink(value: Route.article(item.id)) {
                                    ArticleRow(summary: item, download: env.saved.download(for: item.id))
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                                .simultaneousGesture(TapGesture().onEnded { model.scrollAnchor = item.id })
                                .onAppear { if item.id == items.last?.id { Task { await model.loadMore() } } }
                                RowSeparator()
                            }
                            if model.isLoadingMore { ProgressView().frame(maxWidth: .infinity).padding() }
                        }
                    }
                }
                .padding(.horizontal, sizeClass == .regular ? 32 : 16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .onAppear { if let anchor = model.scrollAnchor { proxy.scrollTo(anchor, anchor: .center) } }
        }
        .refreshable { await model.reload() }
        .screenBackground()
        .navigationTitle(name)
        .task { await model.loadIfNeeded() }
    }
}
