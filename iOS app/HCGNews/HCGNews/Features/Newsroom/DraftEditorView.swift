import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import NewsCore
import NewsAppModel
import Newsroom

struct DraftEditorScreen: View {
    let draftID: UUID
    @Environment(NewsAppEnvironment.self) private var env
    @State private var editor: DraftEditorModel?
    @State private var missing = false

    var body: some View {
        Group {
            if let editor {
                DraftEditorView(editor: editor)
            } else if missing {
                MessageStateView(title: "Draft not found", message: "This local draft no longer exists on this device.", systemImage: "doc.questionmark")
            } else {
                LoadingStateView()
            }
        }
        .task(id: draftID) {
            if let draft = await env.newsroom.store.draft(draftID) {
                editor = DraftEditorModel(draft: draft, store: env.newsroom.store)
                await editor?.loadSnapshots()
            } else {
                missing = true
            }
        }
    }
}

struct DraftEditorView: View {
    @Bindable var editor: DraftEditorModel
    @Environment(NewsAppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPreview = false
    @State private var showingVersions = false
    @State private var showingExporter = false
    @State private var exportDocument: DataDocument?
    @State private var coverItem: PhotosPickerItem?
    @State private var pendingAction: NewsroomAction?
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var actionNote = ""

    var body: some View {
        let newsroom = env.newsroom
        Form {
            Section {
                statusLine
            }
            Section("Headline and introduction") {
                TextField("Headline", text: $editor.draft.headline, axis: .vertical)
                    .accessibilityIdentifier("draftHeadline")
                    .font(Typography.headline(.title3))
                TextField("Introduction (standfirst)", text: $editor.draft.standfirst, axis: .vertical)
            }
            metadataSection
            coverSection
            bodySection
            attachmentsSection
            remoteSection(newsroom)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(editor.draft.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingPreview) { previewSheet }
        .sheet(isPresented: $showingVersions) { versionsSheet }
        .sheet(item: $pendingAction) { action in actionReviewSheet(action) }
        .sheet(item: Binding(get: { newsroom.conflict }, set: { if $0 == nil { newsroom.dismissConflict() } })) { conflict in
            ConflictSheet(conflict: conflict)
        }
        .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json,
                      defaultFilename: "\(editor.draft.displayTitle).hcgnews-draft.json") { _ in }
        .onChange(of: coverItem) { _, item in Task { await attachCover(item) } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await editor.flushAutosave() } } }
        .onDisappear { Task { if editor.isDirty { await editor.save() }; await newsroom.reload() } }
    }

    // MARK: Sections

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(editor.draft.stateLabel).font(.subheadline.weight(.semibold))
            Text(editor.isDirty ? "Unsaved changes · protected by autosave" : "Saved on this device \(editor.lastSavedAt.map { NewsDate.short($0) } ?? "")")
                .font(.footnote).foregroundStyle(Palette.secondaryText)
            Text("Saving keeps this draft on this device. It is not submitted or published.")
                .font(.caption).foregroundStyle(Palette.secondaryText)
            if let error = editor.error { Text(error).font(.footnote).foregroundStyle(Palette.destructive) }
        }
        .accessibilityElement(children: .combine)
    }

    private var metadataSection: some View {
        Section("Section, type and byline") {
            Picker("Section", selection: Binding(
                get: { editor.draft.sectionSlug ?? "" },
                set: { slug in
                    editor.draft.sectionSlug = slug.isEmpty ? nil : slug
                    editor.draft.sectionName = sections.first { $0.slug == slug }?.name
                })) {
                Text("Choose a section").tag("")
                ForEach(sections) { Text($0.name).tag($0.slug) }
                if let slug = editor.draft.sectionSlug, !sections.contains(where: { $0.slug == slug }) {
                    Text(editor.draft.sectionName ?? slug).tag(slug)
                }
            }
            Picker("Editorial type", selection: Binding(
                get: { editor.draft.editorialTypeWire ?? "" },
                set: { editor.draft.editorialTypeWire = $0.isEmpty ? nil : $0 })) {
                Text("Choose a type").tag("")
                ForEach(EditorTypes.all, id: \.self) { Text(EditorialType(rawValue: $0).label).tag($0) }
            }
            let authors = env.newsroom.capabilities?.authors ?? []
            if authors.isEmpty {
                Text("Bylines are chosen from authors HCG has verified. The list appears when the newsroom service is available.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
                ForEach(editor.draft.authors) { Text("By \($0.name)").font(.footnote) }
            } else {
                ForEach(authors) { author in
                    Toggle(isOn: Binding(
                        get: { editor.draft.authors.contains(author) },
                        set: { on in
                            if on { editor.draft.authors.append(author) } else { editor.draft.authors.removeAll { $0 == author } }
                        })) {
                        VStack(alignment: .leading) {
                            Text(author.name)
                            if let title = author.title { Text(title).font(.caption).foregroundStyle(Palette.secondaryText) }
                        }
                    }
                }
            }
            if editor.draft.editorialType == .sponsored {
                Label("Sponsored content is labelled as such to readers.", systemImage: "megaphone")
                    .font(.footnote).foregroundStyle(Palette.warning)
            }
        }
    }

    private var sections: [NewsSection] {
        let fromNewsroom = env.newsroom.capabilities?.sections ?? []
        return fromNewsroom.isEmpty ? env.sections.allSections : fromNewsroom
    }

    private var coverSection: some View {
        Section("Cover image") {
            if let id = editor.draft.cover?.attachmentID, let attachment = editor.draft.attachments.first(where: { $0.id == id }) {
                LocalAttachmentImage(draftID: editor.draft.id, attachmentID: id, store: env.newsroom.store)
                    .frame(maxHeight: 220)
                Text(attachment.filename).font(.caption).foregroundStyle(Palette.secondaryText)
                imageMetaFields(Binding(get: { editor.draft.cover ?? DraftImageMeta() }, set: { editor.draft.cover = $0 }))
                Button("Remove Cover Image", role: .destructive) { editor.draft.cover = nil }
            } else {
                PhotosPicker(selection: $coverItem, matching: .images) {
                    Label("Choose Cover Image", systemImage: "photo")
                }
                Text("Editorial artwork is shown at its own proportions, never cropped or overlaid with the headline.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func imageMetaFields(_ meta: Binding<DraftImageMeta>) -> some View {
        TextField("Alt text (describes the image for VoiceOver)", text: meta.altText, axis: .vertical)
        TextField("Caption", text: meta.caption, axis: .vertical)
        TextField("Credit", text: meta.credit)
    }

    private var bodySection: some View {
        Section {
            ForEach($editor.draft.blocks) { $block in
                BlockEditor(block: $block, draftID: editor.draft.id, store: env.newsroom.store,
                            attach: { data, name, mime in await editor.attach(data: data, filename: name, mimeType: mime) },
                            imageMeta: imageMetaFields)
                    .contextMenu {
                        Button("Move Up") { editor.moveBlock(block.id, by: -1) }
                        Button("Move Down") { editor.moveBlock(block.id, by: 1) }
                        Button("Delete Block", role: .destructive) { editor.removeBlock(block.id) }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { editor.removeBlock(block.id) } }
            }
            Menu {
                ForEach(DraftBlockKind.allCases, id: \.self) { kind in
                    Button(kind.title) { editor.addBlock(kind) }
                }
            } label: {
                Label("Add Block", systemImage: "plus")
            }
        } header: {
            Text("Article body")
        } footer: {
            Text(verbatim: "Use **bold**, *italic* and [link text](https://…) inside text. Long-press a block to move or delete it.")
        }
    }

    private var attachmentsSection: some View {
        Section("Media on this device") {
            if editor.draft.attachments.isEmpty {
                Text("No media attached.").font(.footnote).foregroundStyle(Palette.secondaryText)
            }
            ForEach(editor.draft.attachments) { attachment in
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename)
                    Text("\(ByteSize.string(Int64(attachment.byteCount))) · \(uploadText(attachment.uploadState))")
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                }
                .swipeActions { Button("Remove", role: .destructive) { Task { await editor.removeAttachment(attachment.id) } } }
            }
        }
    }

    private func uploadText(_ state: UploadState) -> String {
        switch state {
        case .localOnly: "On this device only"
        case .uploading: "Uploading…"
        case .uploaded: "Uploaded to the newsroom"
        case .failed(let reason): "Upload failed: \(reason)"
        }
    }

    @ViewBuilder
    private func remoteSection(_ newsroom: NewsroomModel) -> some View {
        Section {
            if let outcome = newsroom.lastOutcome {
                switch outcome {
                case .succeeded(let message): Label(message, systemImage: "checkmark.circle").foregroundStyle(Palette.accent).font(.footnote)
                case .failed(let message): Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.warning).font(.footnote)
                }
            }
            ForEach([NewsroomAction.saveDraft, .submitForReview, .approve, .schedule, .publish, .correct, .unpublish]) { action in
                let availability = newsroom.availability(action)
                VStack(alignment: .leading, spacing: 2) {
                    Button(action.title, role: action.isDestructive ? .destructive : nil) {
                        newsroom.clearOutcome()
                        if action == .saveDraft {
                            Task { await editor.save(); await newsroom.saveToNewsroom(editor.draft.id); await refresh() }
                        } else {
                            pendingAction = action
                        }
                    }
                    .disabled(!availability.isAvailable || newsroom.isWorking || (action != .saveDraft && editor.draft.serverLink == nil))
                    if let reason = availability.reason {
                        Text(reason).font(.caption).foregroundStyle(Palette.secondaryText)
                    }
                }
            }
            if !editor.draft.submissionProblems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Before submitting:").font(.caption.weight(.semibold))
                    ForEach(editor.draft.submissionProblems, id: \.self) { Text("• " + $0).font(.caption) }
                }
                .foregroundStyle(Palette.secondaryText)
            }
            Button { Task { await exportDraft() } } label: { Label("Export Draft File", systemImage: "square.and.arrow.up") }
        } header: {
            Text("Newsroom")
        } footer: {
            Text("Nothing is sent automatically. Each action runs only when you choose it, and the newsroom checks your permission again on the server.")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { Task { await editor.save() } } label: { Label("Save Locally", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s", modifiers: .command)
            Button { Task { showingPreview = true } } label: { Label("Preview", systemImage: "eye") }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Menu {
                Button { Task { await editor.takeSnapshot() } } label: { Label("Save Version Snapshot", systemImage: "camera") }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button { showingVersions = true } label: { Label("Versions…", systemImage: "clock.arrow.circlepath") }
                Button { Task { await exportDraft() } } label: { Label("Export Draft File", systemImage: "square.and.arrow.up") }
            } label: { Label("More", systemImage: "ellipsis.circle") }
        }
    }

    // MARK: Sheets

    private var previewSheet: some View {
        NavigationStack {
            DraftPreview(editor: editor)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingPreview = false } } }
        }
        .environment(env)
    }

    private var versionsSheet: some View {
        NavigationStack {
            List {
                if editor.snapshots.isEmpty {
                    Text("No snapshots yet. Snapshots are taken automatically every few minutes while saving, and whenever you choose Save Version Snapshot.")
                        .font(.footnote).foregroundStyle(Palette.secondaryText)
                }
                ForEach(editor.snapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.headline).font(.headline)
                        Text("\(NewsDate.full(snapshot.createdAt)) · \(snapshot.reason)").font(.caption).foregroundStyle(Palette.secondaryText)
                        Button("Restore This Version") { Task { await editor.restore(snapshot); showingVersions = false } }
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Versions")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingVersions = false } } }
            .task { await editor.loadSnapshots() }
        }
    }

    /// Review of the affected article before any editorial action. Destructive
    /// actions need an explicit confirmation; the server checks permission again.
    private func actionReviewSheet(_ action: NewsroomAction) -> some View {
        NavigationStack {
            Form {
                Section("Affected article") {
                    Text(editor.draft.displayTitle).font(Typography.headline(.headline))
                    if let link = editor.draft.serverLink {
                        LabeledContent("Newsroom status", value: link.remoteStatus.replacingOccurrences(of: "_", with: " "))
                        LabeledContent("Revision", value: link.serverRevision)
                    }
                    if let type = editor.draft.editorialType { LabeledContent("Type", value: type.label) }
                    if let section = editor.draft.sectionName { LabeledContent("Section", value: section) }
                }
                if action == .schedule {
                    Section("Publication time") {
                        DatePicker("Publish at", selection: $scheduleDate, in: Date()...)
                    }
                }
                if action == .correct || action == .unpublish {
                    Section(action == .correct ? "Correction text (shown to readers)" : "Reason (for the newsroom record)") {
                        TextField(action == .correct ? "What was corrected" : "Reason", text: $actionNote, axis: .vertical)
                    }
                }
                Section {
                    Button(role: action.isDestructive ? .destructive : nil) {
                        let note = actionNote
                        let when = action == .schedule ? scheduleDate : nil
                        pendingAction = nil
                        Task {
                            await env.newsroom.perform(action, draftID: editor.draft.id, scheduleAt: when, note: note.isEmpty ? nil : note)
                            await refresh()
                        }
                    } label: {
                        Text(confirmTitle(action))
                    }
                    .disabled(action == .correct && actionNote.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    Text(action.isDestructive
                         ? "This changes what readers see. The newsroom will check your permission before applying it."
                         : "The newsroom will check your permission before applying it.")
                }
            }
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pendingAction = nil } } }
        }
    }

    private func confirmTitle(_ action: NewsroomAction) -> String {
        switch action {
        case .publish: "Publish This Article"
        case .unpublish: "Unpublish This Article"
        case .correct: "Issue Correction"
        case .schedule: "Schedule Publication"
        case .submitForReview: "Submit for Review"
        case .approve: "Approve"
        default: action.title
        }
    }

    // MARK: Actions

    private func refresh() async {
        if let fresh = await env.newsroom.store.draft(editor.draft.id), !editor.isDirty {
            editor.reload(from: fresh)
        }
    }

    private func exportDraft() async {
        await editor.save()
        if let data = try? await env.newsroom.export(editor.draft.id) {
            exportDocument = DataDocument(data: data)
            showingExporter = true
        }
    }

    private func attachCover(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        let type = item.supportedContentTypes.first
        let mime = type?.preferredMIMEType ?? "image/jpeg"
        let ext = type?.preferredFilenameExtension ?? "jpg"
        if let attachment = await editor.attach(data: data, filename: "cover.\(ext)", mimeType: mime) {
            var meta = editor.draft.cover ?? DraftImageMeta()
            meta.attachmentID = attachment.id
            editor.draft.cover = meta
        }
        coverItem = nil
    }
}

/// Editor for one body block.
struct BlockEditor<Meta: View>: View {
    @Binding var block: DraftBlock
    let draftID: UUID
    let store: DraftStore
    /// Adds a file to the draft (updates its attachment list).
    let attach: (Data, String, String) async -> MediaAttachment?
    let imageMeta: (Binding<DraftImageMeta>) -> Meta
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.kind.title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Palette.silver)
            switch block.kind {
            case .heading:
                TextField("Subheading", text: $block.text, axis: .vertical).font(Typography.headline(.headline))
            case .paragraph:
                TextField("Paragraph", text: $block.text, axis: .vertical).lineLimit(3...)
            case .bulletList, .numberedList:
                TextField("One item per line", text: $block.text, axis: .vertical).lineLimit(2...)
            case .quote:
                TextField("Quotation", text: $block.text, axis: .vertical).italic()
                TextField("Attribution", text: $block.attribution)
            case .image:
                let meta = Binding(get: { block.image ?? DraftImageMeta() }, set: { block.image = $0 })
                if let id = block.image?.attachmentID {
                    LocalAttachmentImage(draftID: draftID, attachmentID: id, store: store).frame(maxHeight: 180)
                    imageMeta(meta)
                } else {
                    PhotosPicker(selection: $pickerItem, matching: .images) { Label("Choose Image", systemImage: "photo") }
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                let type = item.supportedContentTypes.first
                guard let attachment = await attach(data, "image.\(type?.preferredFilenameExtension ?? "jpg")",
                                                    type?.preferredMIMEType ?? "image/jpeg") else { return }
                var meta = block.image ?? DraftImageMeta()
                meta.attachmentID = attachment.id
                block.image = meta
                pickerItem = nil
            }
        }
    }
}

/// Shows an attachment stored with a local draft.
struct LocalAttachmentImage: View {
    let draftID: UUID
    let attachmentID: UUID
    let store: DraftStore
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Palette.surface).frame(height: 80)
            }
        }
        .accessibilityHidden(true)
        .task(id: attachmentID) {
            if let url = await store.attachmentURL(draft: draftID, attachment: attachmentID), let data = try? Data(contentsOf: url) {
                image = UIImage(data: data)
            }
        }
    }
}

/// Native reader preview of a local draft.
struct DraftPreview: View {
    let editor: DraftEditorModel
    @State private var article: Article?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Label("Preview — local draft, not published", systemImage: "eye")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.warning)
                    .padding(.bottom, 16)
                if let article {
                    ArticleHeader(summary: article.summary)
                    if let image = article.summary.image { ArticleFigure(image: image).padding(.top, 20) }
                    ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                        ContentBlockView(block: block, canonicalURL: nil).padding(.top, 18)
                    }
                    Text("Author disclosures, if any, are added by the publication from the verified author record.")
                        .font(.caption).foregroundStyle(Palette.secondaryText).padding(.top, 24)
                } else {
                    LoadingStateView()
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .task { article = await editor.previewArticle() }
    }
}

/// Explicit resolution of a revision conflict. Nothing on the server is overwritten.
struct ConflictSheet: View {
    let conflict: DraftConflict
    @Environment(NewsAppEnvironment.self) private var env

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The newsroom has a newer version of this draft (revision \(conflict.server.revision)\(conflict.server.updatedBy.map { ", by \($0)" } ?? "")). Your changes were not sent, and nothing was overwritten.")
                }
                Section {
                    Button("Keep My Version as a Separate Local Draft") { Task { await env.newsroom.resolveConflictKeepingMineAsCopy() } }
                    Button("Load the Newsroom Version (Mine Is Kept as a Snapshot)") { Task { await env.newsroom.resolveConflictLoadingServerVersion() } }
                    Button("Decide Later", role: .cancel) { env.newsroom.dismissConflict() }
                }
            }
            .navigationTitle("Newer Version in Newsroom")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
