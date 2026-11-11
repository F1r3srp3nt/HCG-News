import SwiftUI
import UniformTypeIdentifiers
import NewsCore
import NewsAppModel
import Newsroom

/// The newsroom workspace: separate from reader navigation.
/// Local drafting always works; remote actions appear only when HCG and the
/// newsroom service support and authorise them.
struct NewsroomWorkspace: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: UUID?
    @State private var path: [UUID] = []
    @State private var showingImporter = false
    @State private var importMessage: String?
    @State private var showingAdmin = false

    var body: some View {
        let newsroom = env.newsroom
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    DraftListView(selection: $selection, onOpen: { selection = $0 })
                        .toolbar { workspaceToolbar(newsroom) }
                } detail: {
                    if let selection {
                        DraftEditorScreen(draftID: selection).id(selection)
                    } else {
                        MessageStateView(title: "Choose or create a draft",
                                         message: "Drafts are saved on this device as local drafts. Saving is never submission or publication.",
                                         systemImage: "square.and.pencil")
                    }
                }
            } else {
                NavigationStack(path: $path) {
                    DraftListView(selection: .constant(nil), onOpen: { path.append($0) })
                        .toolbar { workspaceToolbar(newsroom) }
                        .navigationDestination(for: UUID.self) { DraftEditorScreen(draftID: $0) }
                }
            }
        }
        .task {
            await newsroom.reload()
            await newsroom.loadCapabilities()
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            Task {
                guard case .success(let url) = result else { importMessage = "The file couldn't be opened."; return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let draft = try await newsroom.importDraft(data)
                    importMessage = "Imported “\(draft.displayTitle)” as a new local draft."
                    open(draft.id)
                } catch DraftStoreError.unsupportedExportVersion(let v) {
                    importMessage = "This draft file uses format version \(v), which this version of HCG News can't read."
                } catch DraftStoreError.invalidExport(let reason) {
                    importMessage = reason
                } catch {
                    importMessage = "The draft file couldn't be imported."
                }
            }
        }
        .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK") { importMessage = nil }
        } message: { Text(importMessage ?? "") }
        .sheet(isPresented: $showingAdmin) {
            NavigationStack { AdministrationView() }
                .environment(env)
                .hcgThemed()
        }
    }

    private func open(_ id: UUID) {
        if sizeClass == .regular { selection = id } else { path = [id] }
    }

    @ToolbarContentBuilder
    private func workspaceToolbar(_ newsroom: NewsroomModel) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { router.isShowingNewsroom = false }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { if let draft = await newsroom.create() { open(draft.id) } }
            } label: { Label("New Draft", systemImage: "square.and.pencil") }
            .keyboardShortcut("n", modifiers: .command)
            Menu {
                Button { showingImporter = true } label: { Label("Import Draft File…", systemImage: "square.and.arrow.down") }
                Button { showingAdmin = true } label: { Label("Administration", systemImage: "building.columns") }
            } label: { Label("More", systemImage: "ellipsis.circle") }
        }
    }
}

struct DraftListView: View {
    @Binding var selection: UUID?
    let onOpen: (UUID) -> Void
    @Environment(NewsAppEnvironment.self) private var env
    @State private var confirmDelete: Draft?

    var body: some View {
        let newsroom = env.newsroom
        @Bindable var bindable = newsroom
        List(selection: $selection) {
            Section {
                RemoteStatusSummary()
            }
            if !newsroom.recoveries.isEmpty {
                Section("Unsaved changes found") {
                    ForEach(newsroom.recoveries) { draft in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(draft.displayTitle).font(.headline)
                            Text("Changes from \(NewsDate.full(draft.updatedAt)) weren't saved before the app closed.")
                                .font(.footnote).foregroundStyle(Palette.secondaryText)
                            HStack {
                                Button("Recover") { Task { await newsroom.recover(draft.id) } }.buttonStyle(SecondaryButtonStyle())
                                Button("Discard", role: .destructive) { Task { await newsroom.discardRecovery(draft.id) } }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section {
                Picker("Show", selection: $bindable.filter.link) {
                    Text("All drafts").tag(DraftFilter.Link.all)
                    Text("Local only").tag(DraftFilter.Link.localOnly)
                    Text("Linked to newsroom").tag(DraftFilter.Link.linked)
                    Text("Changes not sent").tag(DraftFilter.Link.unsynced)
                }
                Picker("Type", selection: $bindable.filter.editorialTypeWire) {
                    Text("Any type").tag(String?.none)
                    ForEach(EditorTypes.all, id: \.self) { Text(EditorialType(rawValue: $0).label).tag(String?.some($0)) }
                }
            }
            Section {
                if newsroom.filteredDrafts.isEmpty {
                    Text(newsroom.drafts.isEmpty ? "No local drafts yet. Tap New Draft to start writing." : "No drafts match.")
                        .font(.footnote).foregroundStyle(Palette.secondaryText)
                }
                ForEach(newsroom.filteredDrafts) { draft in
                    Button { onOpen(draft.id) } label: { DraftRow(draft: draft) }
                        .buttonStyle(.plain)
                        .tag(draft.id)
                        .swipeActions {
                            Button("Delete", role: .destructive) { confirmDelete = draft }
                        }
                }
            } header: {
                Text("Drafts on this device")
            }
        }
        .searchable(text: $bindable.filter.query, prompt: "Search drafts")
        .navigationTitle("Newsroom")
        .confirmationDialog("Delete this local draft?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { draft in
            Button("Delete “\(draft.displayTitle)”", role: .destructive) {
                Task { await newsroom.delete(draft.id); if selection == draft.id { selection = nil } }
            }
        } message: { draft in
            Text(draft.serverLink == nil
                 ? "It exists only on this device and can't be recovered. Export it first if you may need it."
                 : "This deletes only the copy on this device. The newsroom draft is not changed.")
        }
    }
}

enum EditorTypes {
    static let all = ["news", "analysis", "opinion", "sponsored", "announcement"]
}

struct DraftRow: View {
    let draft: Draft

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let type = draft.editorialType { EditorialLabel(type: type) }
                if let section = draft.sectionName { Text(section).font(Typography.kicker).foregroundStyle(Palette.secondaryText) }
            }
            Text(draft.displayTitle).font(Typography.headline(.headline)).foregroundStyle(Palette.primaryText)
            Text(draft.stateLabel).font(.caption.weight(.semibold)).foregroundStyle(draft.serverLink == nil ? Palette.secondaryText : Palette.accent)
            Text("\(draft.wordCount) words · edited \(NewsDate.short(draft.updatedAt))")
                .font(.caption).foregroundStyle(Palette.secondaryText)
            if let note = draft.detachedNote { Text(note).font(.caption).foregroundStyle(Palette.warning) }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Why remote newsroom actions are or aren't available, in plain words.
struct RemoteStatusSummary: View {
    @Environment(NewsAppEnvironment.self) private var env

    var body: some View {
        let availability = env.newsroom.availability(.saveDraft)
        VStack(alignment: .leading, spacing: 6) {
            Label(availability.isAvailable ? "Connected to the newsroom" : "Local drafting only",
                  systemImage: availability.isAvailable ? "checkmark.circle" : "iphone")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(availability.isAvailable ? Palette.accent : Palette.primaryText)
            Text(availability.reason ?? "Remote actions are offered only when the newsroom service supports them and has authorised them for your account.")
                .font(.footnote).foregroundStyle(Palette.secondaryText)
            if let error = env.newsroom.capabilitiesError {
                Text(error).font(.footnote).foregroundStyle(Palette.warning)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Administration

/// Administration driven by verified central capabilities. Native administration
/// appears only where a real endpoint exists; otherwise HCG's own destinations are linked.
struct AdministrationView: View {
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let admin = env.admin
        Form {
            Section("Publication") {
                LabeledContent("Content connection") { ConnectionBadge(status: env.connection.publication) }
                Button("Check Connection") { Task { await env.connection.checkAll() } }
            }
            Section("Access and licence (from HCG)") {
                if let decision = env.account.decision {
                    LabeledContent("HCG News access", value: AccessText.label(decision.status))
                    if let org = decision.currentOrganization { LabeledContent("Organisation", value: org.name) }
                    ForEach(decision.entitlements ?? []) { item in LabeledContent(item.name, value: item.status) }
                } else {
                    Text(env.account.isSignedIn ? "HCG hasn't returned an access decision in this session." : "Sign in with HCG Connect to see access and licence information.")
                        .font(.footnote).foregroundStyle(Palette.secondaryText)
                }
            }
            Section("Editorial queue (from the newsroom)") {
                if let reason = admin.queueUnavailable {
                    Text(reason).font(.footnote).foregroundStyle(Palette.secondaryText)
                }
                switch admin.queue {
                case .loading: ProgressView()
                case .loaded(let items) where items.isEmpty: Text("The queue is empty.").font(.footnote)
                case .loaded(let items):
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.headline)
                            Text("\(item.status.replacingOccurrences(of: "_", with: " ")) · revision \(item.revision)" + (item.updatedBy.map { " · \($0)" } ?? ""))
                                .font(.caption).foregroundStyle(Palette.secondaryText)
                        }
                    }
                default: EmptyView()
                }
            }
            Section("Sections, authors and media") {
                ForEach([NewsroomAction.manageSections, .manageAuthors, .manageMedia]) { action in
                    LabeledContent(action.title, value: env.newsroom.availability(action).isAvailable ? "Available in HCG" : "Not available in the app")
                }
                if env.managementLinks.isEmpty {
                    Text("Native administration isn't available. HCG hasn't configured management links for this app.")
                        .font(.footnote).foregroundStyle(Palette.secondaryText)
                }
                ForEach(env.managementLinks) { link in
                    Link(destination: link.url) { Label(link.title, systemImage: "safari") }
                }
                if let newsroom = env.account.status?.newsroomURL {
                    Link(destination: newsroom) { Label("HCG newsroom (web)", systemImage: "safari") }
                }
            }
            Section {
                if let reason = admin.auditUnavailable {
                    Text(reason).font(.footnote).foregroundStyle(Palette.secondaryText)
                }
                if case .loaded(let entries) = admin.audit {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.actor): \(entry.action)").font(.footnote)
                            Text(NewsDate.full(entry.at) + (entry.detail.map { " · \($0)" } ?? "")).font(.caption2).foregroundStyle(Palette.secondaryText)
                        }
                    }
                }
            } header: {
                Text("Audit history (newsroom server)")
            } footer: {
                Text("Recorded by the newsroom service. Shown only when it provides an audit endpoint.")
            }
            Section {
                ForEach(admin.localEvents.prefix(30)) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.message).font(.footnote)
                        Text("\(NewsDate.full(event.at)) · \(event.category.rawValue)").font(.caption2).foregroundStyle(Palette.secondaryText)
                    }
                }
                if admin.localEvents.isEmpty { Text("No events.").font(.footnote).foregroundStyle(Palette.secondaryText) }
                Button("Clear Device History", role: .destructive) { Task { await admin.clearLocalEvents() } }
            } header: {
                Text("Troubleshooting history (this device only)")
            } footer: {
                Text("What this app did on this device. Not the server's audit history.")
            }
        }
        .screenBackground()
        .navigationTitle("Administration")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await admin.reload() }
    }
}
