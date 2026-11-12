import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import NewsCore
import NewsAppModel
import HCGPlatform

/// The newsroom on HCG: the same articles, roles and rules as the HCG News website's
/// newsroom. Shown only to people HCG gave a newsroom role in this session.
struct NewsroomDeskView: View {
    let desk: NewsroomDeskModel
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var path: [String] = []
    @State private var showingAdmin = false
    @State private var showingLocalDrafts = false

    var body: some View {
        @Bindable var desk = desk
        NavigationStack(path: $path) {
            content
                .navigationTitle("Newsroom")
                .searchable(text: $desk.searchText, prompt: "Search headlines, authors, sections")
                .refreshable { await desk.load() }
                .toolbar { toolbar }
                .navigationDestination(for: String.self) { id in
                    RemoteArticleEditorScreen(desk: desk, articleID: id)
                }
        }
        .task { if desk.phase == .idle { await desk.load() } }
        .onChange(of: env.platformAccount?.currentPermissions.isStaff ?? false) { _, isStaff in
            // Access removed centrally (a completed check said no role) or signed out: close.
            if !isStaff { router.isShowingNewsroom = false }
        }
        .sheet(isPresented: $showingAdmin) {
            NavigationStack { NewsroomAdminView(desk: desk) }
                .environment(env).hcgThemed()
        }
        .sheet(isPresented: $showingLocalDrafts) {
            NewsroomWorkspace(onClose: { showingLocalDrafts = false })
                .environment(env).environment(router).hcgThemed()
        }
        .alert("Newsroom", isPresented: Binding(get: { desk.message != nil }, set: { if !$0 { desk.dismissMessage() } })) {
            Button("OK") { desk.dismissMessage() }
        } message: { Text(desk.message ?? "") }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var desk = desk
        switch desk.phase {
        case .idle, .loading where desk.articles.isEmpty:
            LoadingStateView()
        case .failed(let message) where desk.articles.isEmpty:
            MessageStateView(title: "Newsroom unavailable", message: message, systemImage: "exclamationmark.triangle",
                             retry: { await desk.load() })
        default:
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(desk.permissions.orderedRoles.map(\.title).joined(separator: " · "))
                            .font(.subheadline.weight(.semibold))
                        Text("Changes reach HCG only when you tap Save. Publishing, scheduling and archiving always ask for confirmation. HCG checks every action again.")
                            .font(.footnote).foregroundStyle(Palette.secondaryText)
                    }
                    Picker("Show", selection: $desk.filter) {
                        ForEach(NewsroomDeskModel.Filter.allCases) { Text($0.title).tag($0) }
                    }
                }
                if case .failed(let message) = desk.phase {
                    Section { Label(message, systemImage: "exclamationmark.triangle").font(.footnote) }
                }
                Section {
                    let items = desk.visibleArticles
                    if items.isEmpty {
                        Text("No articles match.").foregroundStyle(Palette.secondaryText)
                    }
                    ForEach(items) { item in
                        NavigationLink(value: item.id) {
                            DeskRow(item: item, hasLocalEdits: desk.unsavedArticleIDs.contains(item.id))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .screenBackground()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { router.isShowingNewsroom = false }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { if let editor = await desk.createDraft() { path.append(editor.id) } }
            } label: { Label("New Draft", systemImage: "square.and.pencil") }
            .disabled(desk.isCreating || !desk.permissions.isStaff)
            .keyboardShortcut("n", modifiers: .command)
            Menu {
                if desk.permissions.canManageSections || desk.permissions.canViewAudit {
                    Button { showingAdmin = true } label: { Label("Administration", systemImage: "building.columns") }
                }
                Button { showingLocalDrafts = true } label: { Label("Local Drafts on This Device", systemImage: "iphone") }
            } label: { Label("More", systemImage: "ellipsis.circle") }
        }
    }
}

struct DeskRow: View {
    let item: NewsroomArticleSummary
    let hasLocalEdits: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EditorialStatusBadge(status: item.status, publishedAt: item.publishedAt)
                if item.isBreaking { StatusBadge(text: "Breaking", tone: .attention) }
                if item.isFeatured { StatusBadge(text: "Featured") }
                if item.isDemo { StatusBadge(text: "Demo content") }
            }
            Text(item.title).font(Typography.headline(.headline)).foregroundStyle(Palette.primaryText)
            Text([item.sectionName, item.authorName, item.updatedAt.map { "Updated " + NewsDate.short($0) }]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Palette.secondaryText)
            if hasLocalEdits {
                Label("Unsaved edits on this device", systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.warning)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Draft / In Review / Approved / Scheduled / Published / Archived.
struct EditorialStatusBadge: View {
    let status: String
    let publishedAt: Date?

    var body: some View {
        let (text, tone) = describe()
        StatusBadge(text: text, tone: tone)
    }

    private func describe() -> (String, StatusBadge.Tone) {
        switch EditorialStatus(rawValue: status) {
        case .published?:
            if let publishedAt, publishedAt > Date() { return ("Scheduled · \(NewsDate.full(publishedAt))", .attention) }
            return ("Published", .good)
        case .some(let s): return (s.title, .neutral)
        case nil: return (status, .problem)
        }
    }
}

// MARK: - Editor

struct RemoteArticleEditorScreen: View {
    let desk: NewsroomDeskModel
    let articleID: String
    @State private var editor: RemoteArticleEditorModel?
    @State private var failed: String?

    var body: some View {
        Group {
            if let editor {
                RemoteArticleEditorView(editor: editor)
            } else if let failed {
                MessageStateView(title: "Article unavailable", message: failed, systemImage: "doc.questionmark",
                                 retry: { await load() })
            } else {
                LoadingStateView()
            }
        }
        .task { if editor == nil { await load() } }
    }

    private func load() async {
        failed = nil
        if let model = await desk.openEditor(id: articleID) {
            await model.checkForBackup()
            editor = model
        } else {
            failed = desk.message ?? "The article couldn't be opened."
            desk.dismissMessage()
        }
    }
}

struct RemoteArticleEditorView: View {
    let editor: RemoteArticleEditorModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPreview = false
    @State private var showingVersions = false
    @State private var mediaTarget: MediaTarget?
    @State private var pendingStatus: EditorialStatus?
    @State private var showingPublish = false
    @State private var confirmDiscardBackup = false
    /// A confirmed publication, run after the Publish sheet has fully closed (so a
    /// resulting conflict sheet can present). Outer nil: nothing pending; inner nil: now.
    @State private var pendingPublication: Date??

    enum MediaTarget: Identifiable, Equatable {
        case cover
        case block(UUID)
        case newBlock
        var id: String {
            switch self {
            case .cover: "cover"
            case .block(let id): id.uuidString
            case .newBlock: "new"
            }
        }
    }

    var body: some View {
        @Bindable var editor = editor
        Form {
            statusSection
            Group {
            Section("Story") {
                TextField("Headline", text: $editor.fields.title, axis: .vertical)
                    .font(Typography.headline(.title3))
                    .accessibilityIdentifier("newsroom-headline")
                TextField("Subtitle", text: $editor.fields.subtitle, axis: .vertical)
                TextField("Excerpt (shown on cards and as the standfirst)", text: $editor.fields.excerpt, axis: .vertical)
                HStack {
                    TextField("Slug", text: $editor.fields.slug)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button("From Headline") { editor.fields.slug = NewsroomArticleFields.slugify(editor.fields.title) }
                        .font(.footnote)
                        .buttonStyle(.borderless)
                }
            }
            Section("Classification") {
                Picker("Section", selection: $editor.fields.categoryID) {
                    Text("No section").tag(String?.none)
                    ForEach(editor.sections) { Text($0.name + ($0.isVisible ? "" : " (hidden)")).tag(String?.some($0.id)) }
                }
                Picker("Type", selection: $editor.fields.contentType) {
                    ForEach(["news", "analysis", "opinion", "sponsored", "announcement"], id: \.self) {
                        Text(EditorialType(rawValue: $0).label).tag($0)
                    }
                }
                Picker("Byline", selection: $editor.fields.authorID) {
                    Text("No byline").tag(String?.none)
                    ForEach(editor.authors) { Text($0.name).tag(String?.some($0.id)) }
                }
            }
            bodySection
            coverSection
            Section("Placement") {
                Toggle("Featured on Home", isOn: $editor.fields.isFeatured)
                Toggle("Breaking news", isOn: $editor.fields.isBreaking)
            }
            Section {
                TextField("SEO title", text: $editor.fields.seoTitle)
                TextField("SEO description", text: $editor.fields.seoDescription, axis: .vertical)
                TextField("Tags, separated by commas", text: $editor.tagsText)
                TextField("Sources, one per line", text: $editor.fields.sources, axis: .vertical).lineLimit(2...8)
            } header: { Text("Search and sources") }
            Section {
                TextField("Correction note", text: $editor.fields.correctionNotes, axis: .vertical).lineLimit(1...6)
            } header: { Text("Corrections") } footer: { Text("Shown publicly on the article.") }
            }
            .disabled(!editor.canEdit)
            Section {
                Button { showingVersions = true } label: { Label("Version History", systemImage: "clock.arrow.circlepath") }
                if let url = editor.previewURL {
                    Link(destination: url) { Label("View on the Publication", systemImage: "safari") }
                }
            }
        }
        .screenBackground()
        .navigationTitle(editor.fields.title.isEmpty ? "Untitled article" : editor.fields.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await editor.flushBackup() } } }
        .onDisappear { Task { await editor.flushBackup() } }
        .sheet(isPresented: $showingPreview) {
            NavigationStack { RemoteArticlePreview(article: editor.previewArticle()) }
        }
        .sheet(isPresented: $showingVersions) {
            NavigationStack { VersionHistoryView(editor: editor) }
        }
        .sheet(item: $mediaTarget) { target in
            NavigationStack {
                MediaLibraryPicker(editor: editor) { item in
                    switch target {
                    case .cover: editor.useAsCover(item)
                    case .newBlock: editor.insertImage(item)
                    case .block(let id):
                        if let i = editor.blocks.firstIndex(where: { $0.id == id }), let url = item.url {
                            editor.blocks[i].imageURL = url.absoluteString
                            if editor.blocks[i].altText.isEmpty { editor.blocks[i].altText = item.altText ?? "" }
                            if editor.blocks[i].caption.isEmpty { editor.blocks[i].caption = item.caption ?? "" }
                            if editor.blocks[i].credit.isEmpty { editor.blocks[i].credit = item.credit ?? "" }
                        }
                    }
                    mediaTarget = nil
                }
            }
        }
        .sheet(isPresented: $showingPublish, onDismiss: {
            guard let scheduled = pendingPublication else { return }
            pendingPublication = nil
            Task { await editor.change(to: .published, scheduleAt: scheduled) }
        }) {
            NavigationStack { PublishSheet(editor: editor) { pendingPublication = .some($0) } }
        }
        .confirmationDialog("Discard the unsaved edits stored on this device?", isPresented: $confirmDiscardBackup, titleVisibility: .visible) {
            Button("Discard Edits", role: .destructive) { Task { await editor.discardBackup() } }
        }
        .sheet(isPresented: Binding(get: { if case .conflict = editor.phase { return true } else { return false } }, set: { _ in })) {
            if case .conflict(let server) = editor.phase {
                NavigationStack { RemoteConflictView(editor: editor, server: server) }
                    .interactiveDismissDisabled()
            }
        }
        .confirmationDialog(pendingStatus.map { "Change status to \($0.title)?" } ?? "", isPresented: Binding(
            get: { pendingStatus != nil }, set: { if !$0 { pendingStatus = nil } }), titleVisibility: .visible) {
            if let status = pendingStatus {
                Button(status == .archived ? "Archive" : "Change to \(status.title)", role: status == .archived ? .destructive : nil) {
                    Task { await editor.change(to: status) }
                    pendingStatus = nil
                }
            }
        } message: {
            Text(statusMessage(pendingStatus))
        }
    }

    private func statusMessage(_ status: EditorialStatus?) -> String {
        let unsaved = editor.hasUnsavedChanges ? " Your unsaved edits are saved at the same time." : ""
        switch status {
        case .archived?:
            return (editor.base.isLive() ? "This removes the article from the publication." : "The article moves to the archive.") + unsaved
        case .draft? where editor.base.isLive() || editor.base.isScheduled():
            return "This takes the article off the publication (or cancels its scheduled publication) and returns it to draft." + unsaved
        default:
            return "“\(editor.fields.title)” will be marked \(status?.title ?? "")." + unsaved
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            HStack {
                EditorialStatusBadge(status: editor.base.status, publishedAt: editor.base.publishedAt)
                if editor.base.isDemo { StatusBadge(text: "Demo content") }
                Spacer()
                switch editor.phase {
                case .saving: ProgressView()
                case .saved(let at): Text("Saved \(NewsDate.short(at))").font(.caption).foregroundStyle(Palette.secondaryText)
                default:
                    if editor.hasUnsavedChanges {
                        Text("Unsaved changes").font(.caption.weight(.semibold)).foregroundStyle(Palette.warning)
                    }
                }
            }
            if !editor.canEdit {
                Label("Your HCG News role can view this article but not change it.", systemImage: "lock")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
            }
            if case .failed(let message) = editor.phase {
                Label(message, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Palette.destructive)
            }
            if let notice = editor.notice {
                HStack {
                    Text(notice).font(.footnote)
                    Spacer()
                    Button("Dismiss") { editor.clearNotice() }.font(.footnote).buttonStyle(.borderless)
                }
            }
            if let backup = editor.recoverableBackup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unsaved edits from \(NewsDate.full(backup.savedAt)) are stored on this device.")
                        .font(.footnote.weight(.semibold))
                    HStack {
                        Button("Restore Edits") { editor.recoverBackup() }.buttonStyle(SecondaryButtonStyle())
                        Button("Discard", role: .destructive) { confirmDiscardBackup = true }.buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        @Bindable var editor = editor
        Section {
            switch editor.bodyMode {
            case .readOnly(let reason):
                VStack(alignment: .leading, spacing: 8) {
                    Label(reason, systemImage: "doc.text.magnifyingglass").font(.footnote)
                    Text("The body is left exactly as it is when you save other fields.")
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                    Link("Edit the body in the website newsroom", destination: editor.websiteEditorURL).font(.footnote)
                }
            case .editable:
                ForEach($editor.blocks) { $block in
                    BodyBlockEditor(block: $block, chooseImage: { mediaTarget = .block(block.id) },
                                    moveUp: { editor.moveBlock(block.id, by: -1) },
                                    moveDown: { editor.moveBlock(block.id, by: 1) },
                                    remove: { editor.removeBlock(block.id) })
                }
                Menu {
                    ForEach(EditableBodyBlock.Kind.allCases.filter { $0 != .image }, id: \.self) { kind in
                        Button(kind.title) { editor.blocks.append(EditableBodyBlock(kind: kind)) }
                    }
                    Button("Image from Media Library") { mediaTarget = .newBlock }
                } label: { Label("Add Block", systemImage: "plus") }
            }
        } header: {
            Text("Body")
        } footer: {
            if editor.bodyMode == .editable {
                Text(verbatim: "Formatting: **bold**, *italic*, __underline__, [link text](https://…).")
            }
        }
    }

    @ViewBuilder
    private var coverSection: some View {
        @Bindable var editor = editor
        Section("Cover image") {
            if let url = URL(string: editor.fields.featuredImageURL), url.scheme == "https" {
                AsyncImage(url: url) { image in image.resizable().aspectRatio(contentMode: .fit) } placeholder: { ProgressView() }
                    .frame(maxHeight: 200)
                    .accessibilityLabel(editor.fields.featuredImageAlt)
                TextField("Alt text (required)", text: $editor.fields.featuredImageAlt, axis: .vertical)
                TextField("Caption", text: $editor.fields.featuredImageCaption, axis: .vertical)
                TextField("Credit", text: $editor.fields.featuredImageCredit)
                Button("Remove Cover Image", role: .destructive) {
                    editor.fields.featuredImageURL = ""
                    editor.fields.featuredImageAlt = ""
                    editor.fields.featuredImageCaption = ""
                    editor.fields.featuredImageCredit = ""
                }
            }
            Button { mediaTarget = .cover } label: { Label("Choose from Media Library", systemImage: "photo.on.rectangle") }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await editor.save() }
            } label: { Text("Save") }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!editor.canEdit || !editor.hasUnsavedChanges || editor.phase == .saving)
            .accessibilityIdentifier("newsroom-save")
            Menu {
                Button { showingPreview = true } label: { Label("Preview", systemImage: "eye") }
                let transitions = editor.availableTransitions
                if !transitions.isEmpty {
                    Section("Status") {
                        ForEach(transitions, id: \.self) { status in
                            if status == .published {
                                Button { showingPublish = true } label: { Label("Publish or Schedule…", systemImage: "paperplane") }
                            } else {
                                Button(role: status == .archived ? .destructive : nil) { pendingStatus = status } label: {
                                    Label(label(for: status), systemImage: icon(for: status))
                                }
                            }
                        }
                    }
                }
                Button { Task { await editor.reload() } } label: { Label("Reload from HCG", systemImage: "arrow.clockwise") }
                    .disabled(editor.hasUnsavedChanges)
            } label: { Label("Actions", systemImage: "ellipsis.circle") }
        }
    }

    private func label(for status: EditorialStatus) -> String {
        switch status {
        case .inReview: "Submit for Review"
        case .approved: "Approve"
        case .draft: editor.base.isLive() ? "Unpublish (Return to Draft)" : "Return to Draft"
        case .archived: "Archive"
        case .published: "Publish"
        }
    }

    private func icon(for status: EditorialStatus) -> String {
        switch status {
        case .inReview: "tray.and.arrow.up"
        case .approved: "checkmark.seal"
        case .draft: "arrow.uturn.backward"
        case .archived: "archivebox"
        case .published: "paperplane"
        }
    }
}

struct BodyBlockEditor: View {
    @Binding var block: EditableBodyBlock
    let chooseImage: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(block.kind.title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Palette.silver)
                Spacer()
                Menu {
                    Button { moveUp() } label: { Label("Move Up", systemImage: "arrow.up") }
                    Button { moveDown() } label: { Label("Move Down", systemImage: "arrow.down") }
                    Button(role: .destructive) { remove() } label: { Label("Delete Block", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 32)
                }
                .accessibilityLabel("\(block.kind.title) options")
            }
            switch block.kind {
            case .divider:
                Divider()
            case .image:
                if let url = URL(string: block.imageURL), url.scheme == "https" {
                    AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fit) } placeholder: { ProgressView() }
                        .frame(maxHeight: 160)
                }
                Button("Choose Image…", action: chooseImage).font(.footnote).buttonStyle(.borderless)
                TextField("Alt text (required)", text: $block.altText, axis: .vertical)
                TextField("Caption", text: $block.caption, axis: .vertical)
                TextField("Credit", text: $block.credit)
            case .quote:
                TextField("Quotation", text: $block.text, axis: .vertical)
                TextField("Attribution", text: $block.attribution)
            case .bulletList, .numberedList:
                TextField("One item per line", text: $block.text, axis: .vertical).lineLimit(2...12)
            default:
                TextField(block.kind.title, text: $block.text, axis: .vertical)
                    .font(block.kind == .paragraph ? .body : Typography.headline(.headline))
            }
        }
        .padding(.vertical, 4)
    }
}

struct PublishSheet: View {
    let editor: RemoteArticleEditorModel
    /// Called with nil (publish now) or the scheduled time; the parent runs it once the sheet closes.
    let onConfirm: (Date?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var schedule = false
    @State private var date = Date().addingTimeInterval(3600)
    @State private var confirmed = false

    var body: some View {
        let problems = editor.publicationProblems
        Form {
            Section {
                Text(editor.fields.title).font(Typography.headline(.headline))
                Text("Publication makes this article public on news.hakmicapitalgroup.com and in the app.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
            }
            if !problems.isEmpty {
                Section("Before publishing") {
                    ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.circle").font(.footnote) }
                }
            }
            Section {
                Toggle("Schedule for later", isOn: $schedule)
                if schedule {
                    DatePicker("Publish at", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
                Toggle("I've checked this article and want to \(schedule ? "schedule" : "publish") it", isOn: $confirmed)
            }
            if editor.hasUnsavedChanges {
                Section { Text("Your unsaved edits are saved at the same time.").font(.footnote) }
            }
        }
        .navigationTitle(schedule ? "Schedule" : "Publish")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(schedule ? "Schedule" : "Publish") {
                    onConfirm(schedule ? date : nil)
                    dismiss()
                }
                .disabled(!problems.isEmpty || !confirmed)
            }
        }
    }
}

struct RemoteConflictView: View {
    let editor: RemoteArticleEditorModel
    let server: NewsroomArticle
    @State private var confirmDiscard = false

    var body: some View {
        Form {
            Section {
                Text("Someone else saved this article after you opened it. Nothing has been overwritten, and your edits are stored on this device.")
                    .font(.footnote)
            }
            Section("Their version") {
                LabeledContent("Headline", value: server.fields.title)
                LabeledContent("Status", value: EditorialStatus(rawValue: server.status)?.title ?? server.status)
                if let updated = server.updatedAt { LabeledContent("Saved", value: NewsDate.full(updated)) }
            }
            Section("Your version") {
                LabeledContent("Headline", value: editor.fields.title)
            }
            Section {
                Button("Keep My Edits and Review") { editor.keepMineOverServer() }
                Button("Discard My Edits and Load Theirs", role: .destructive) { confirmDiscard = true }
            } footer: {
                Text("Keeping your edits doesn't save them: review, then tap Save to replace the other changes to the fields you edited.")
            }
        }
        .navigationTitle("Edited Elsewhere")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Discard your edits?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard My Edits", role: .destructive) { Task { await editor.takeServerVersion() } }
        }
    }
}

struct VersionHistoryView: View {
    let editor: RemoteArticleEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && editor.versions.isEmpty {
                Text("No versions were returned for this article.").foregroundStyle(Palette.secondaryText)
            }
            ForEach(editor.versions) { version in
                VStack(alignment: .leading, spacing: 4) {
                    Text(version.title ?? "Untitled").font(.headline)
                    Text([version.status.flatMap { EditorialStatus(rawValue: $0)?.title }, version.createdAt.map(NewsDate.full)]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                    if editor.canEdit {
                        Button("Copy into Editor") { editor.restore(version); dismiss() }.font(.footnote)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Version History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await editor.loadVersions(); loaded = true }
    }
}

struct RemoteArticlePreview: View {
    let article: Article
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Label("Preview — not published", systemImage: "eye")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.warning).padding(.bottom, 16)
                ArticleHeader(summary: article.summary)
                if !article.summary.disclosures.isEmpty { DisclosureBox(disclosures: article.summary.disclosures, authors: article.summary.authors).padding(.top, 16) }
                if let image = article.summary.image { ArticleFigure(image: image).padding(.top, 20) }
                ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                    ContentBlockView(block: block, canonicalURL: nil).padding(.top, 18)
                }
                if !article.corrections.isEmpty { CorrectionsView(corrections: article.corrections).padding(.top, 24) }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

// MARK: - Media

struct MediaLibraryPicker: View {
    let editor: RemoteArticleEditorModel
    let onChoose: (NewsroomMedia) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var pending: (data: Data, mime: String, ext: String)?
    @State private var altText = ""
    @State private var caption = ""
    @State private var credit = ""
    @State private var loadError: String?

    var body: some View {
        List {
            Section {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Upload a Photo", systemImage: "square.and.arrow.up")
                }
                if pending != nil {
                    TextField("Alt text (required)", text: $altText, axis: .vertical)
                    TextField("Caption", text: $caption, axis: .vertical)
                    TextField("Credit", text: $credit)
                    Button {
                        Task {
                            guard let p = pending else { return }
                            if let item = await editor.upload(data: p.data, mimeType: p.mime, fileExtension: p.ext,
                                                              caption: caption, altText: altText, credit: credit) {
                                pending = nil
                                onChoose(item)
                            }
                        }
                    } label: {
                        HStack { if editor.isUploading { ProgressView() }; Text("Upload to HCG News") }
                    }
                    .disabled(editor.isUploading || altText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let loadError { Text(loadError).font(.footnote).foregroundStyle(Palette.destructive) }
                if let notice = editor.notice { Text(notice).font(.footnote) }
            } footer: {
                Text("Images go to the HCG News media library (JPEG, PNG, WebP, GIF or AVIF, up to 20 MB).")
            }
            Section("Media library") {
                if editor.media.isEmpty { Text("No images yet.").foregroundStyle(Palette.secondaryText) }
                ForEach(editor.media) { item in
                    Button { onChoose(item) } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: item.url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Palette.surface }
                                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 6))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.altText ?? "No alt text").font(.subheadline).foregroundStyle(Palette.primaryText)
                                Text([item.caption, item.credit].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Palette.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Media")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task { await editor.loadMedia() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                loadError = nil
                let type = item.supportedContentTypes.first { $0.preferredMIMEType.map(NewsroomRepository.imageTypes.contains) ?? false }
                guard let type, let mime = type.preferredMIMEType,
                      let data = try? await item.loadTransferable(type: Data.self) else {
                    loadError = "This photo's format can't be uploaded. Use JPEG, PNG, WebP, GIF or AVIF."
                    pickerItem = nil
                    return
                }
                if let problem = NewsroomRepository.uploadProblem(mimeType: mime, byteCount: data.count) {
                    loadError = problem
                    pickerItem = nil
                    return
                }
                pending = (data, mime, type.preferredFilenameExtension ?? "jpg")
                pickerItem = nil
            }
        }
    }
}

// MARK: - Administration

struct NewsroomAdminView: View {
    @State private var model: NewsroomAdminDeskModel
    @Environment(\.dismiss) private var dismiss
    @State private var newSection = ""

    init(desk: NewsroomDeskModel) {
        _model = State(initialValue: NewsroomAdminDeskModel(desk: desk))
    }

    var body: some View {
        List {
            if let message = model.message { Section { Text(message).font(.footnote) } }
            Section {
                ForEach(model.sections) { section in
                    SectionAdminRow(section: section, model: model)
                }
                if model.permissions.canManageSections {
                    HStack {
                        TextField("New section name", text: $newSection)
                        Button("Add") { Task { await model.addSection(named: newSection); newSection = "" } }
                            .disabled(newSection.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: { Text("Sections") } footer: {
                Text("Hidden sections don't appear on the publication. Editors-in-Chief and Administrators manage sections.")
            }
            Section {
                if let state = model.auditState { Text(state).font(.footnote).foregroundStyle(Palette.secondaryText) }
                ForEach(model.audit) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.summary ?? entry.action).font(.subheadline)
                        Text([entry.action, entry.entity, entry.createdAt.map(NewsDate.full)].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Palette.secondaryText)
                    }
                }
            } header: { Text("Audit history (HCG News server)") }
        }
        .navigationTitle("Administration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await model.load() }
    }
}

struct SectionAdminRow: View {
    let section: NewsroomCategory
    let model: NewsroomAdminDeskModel
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.permissions.canManageSections {
                TextField("Name", text: $name)
                    .font(.headline)
                    .onSubmit { Task { await model.rename(section, to: name) } }
                Toggle("Visible on the publication", isOn: Binding(
                    get: { section.isVisible }, set: { v in Task { await model.setVisible(section, v) } }))
            } else {
                Text(section.name).font(.headline)
                Text(section.isVisible ? "Visible" : "Hidden").font(.caption).foregroundStyle(Palette.secondaryText)
            }
            Text("/\(section.slug)").font(.caption.monospaced()).foregroundStyle(Palette.secondaryText)
        }
        .onAppear { name = section.name }
    }
}
