import Foundation
import Observation
import NewsCore
import HCGPlatform
import HCGTransport

/// Unsaved edits to newsroom articles, kept on this device per account until they are
/// saved to HCG or discarded, so a crash, a lost connection or a conflict never loses work.
public actor RemoteEditBackupStore {
    public struct Backup: Codable, Equatable, Sendable {
        public let articleID: String
        public let baseRevision: String
        public let fields: NewsroomArticleFields
        public let savedAt: Date
    }

    private let root: URL?

    public init(root: URL?) { self.root = root }

    private func url(user: String, article: String) -> URL? {
        let safe = { (s: String) in s.filter { $0.isLetter || $0.isNumber || $0 == "-" } }
        return root?.appendingPathComponent(safe(user), isDirectory: true).appendingPathComponent(safe(article) + ".json")
    }

    public func save(_ backup: Backup, user: String) {
        guard let url = url(user: user, article: backup.articleID) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? HCGJSON.makeEncoder().encode(backup) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    public func load(user: String, article: String) -> Backup? {
        guard let url = url(user: user, article: article), let data = try? Data(contentsOf: url) else { return nil }
        return try? HCGJSON.makeDecoder().decode(Backup.self, from: data)
    }

    public func remove(user: String, article: String) {
        guard let url = url(user: user, article: article) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public func articleIDs(user: String) -> [String] {
        guard let root else { return [] }
        let dir = root.appendingPathComponent(user.filter { $0.isLetter || $0.isNumber || $0 == "-" }, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }
    }
}

/// The newsroom desk: the articles HCG lets this person see, with filters.
@MainActor
@Observable
public final class NewsroomDeskModel {
    public enum Filter: String, CaseIterable, Sendable, Identifiable {
        case all, mine, drafts, inReview, approved, scheduled, live, archived
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .all: "All"
            case .mine: "Mine"
            case .drafts: "Drafts"
            case .inReview: "In review"
            case .approved: "Approved"
            case .scheduled: "Scheduled"
            case .live: "Published"
            case .archived: "Archived"
            }
        }
    }

    public enum Phase: Equatable, Sendable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var articles: [NewsroomArticleSummary] = []
    public private(set) var phase: Phase = .idle
    public private(set) var unsavedArticleIDs: Set<String> = []
    public var filter: Filter = .all
    public var searchText = ""
    public private(set) var isCreating = false
    public private(set) var message: String?

    @ObservationIgnored public let account: PlatformAccountModel
    @ObservationIgnored let repository: NewsroomRepository
    @ObservationIgnored public let backups: RemoteEditBackupStore
    @ObservationIgnored let publicationURL: URL
    @ObservationIgnored let log: LocalEventLog?
    @ObservationIgnored public private(set) var sections: [NewsroomCategory] = []
    @ObservationIgnored public private(set) var authors: [NewsroomAuthor] = []

    public init(account: PlatformAccountModel, repository: NewsroomRepository, backups: RemoteEditBackupStore,
                publicationURL: URL, log: LocalEventLog?) {
        self.account = account
        self.repository = repository
        self.backups = backups
        self.publicationURL = publicationURL
        self.log = log
    }

    public var permissions: NewsroomPermissions { account.currentPermissions }

    /// Clears everything loaded for the previous account.
    public func reset() {
        articles = []
        sections = []
        authors = []
        unsavedArticleIDs = []
        phase = .idle
        message = nil
    }

    public var visibleArticles: [NewsroomArticleSummary] {
        let now = Date()
        let me = account.user?.id
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return articles.filter { a in
            let matches: Bool
            switch filter {
            case .all: matches = true
            case .mine: matches = me != nil && a.createdBy == me
            case .drafts: matches = a.status == EditorialStatus.draft.rawValue
            case .inReview: matches = a.status == EditorialStatus.inReview.rawValue
            case .approved: matches = a.status == EditorialStatus.approved.rawValue
            case .scheduled: matches = a.isScheduled(now: now)
            case .live: matches = a.isLive(now: now)
            case .archived: matches = a.status == EditorialStatus.archived.rawValue
            }
            guard matches else { return false }
            guard !query.isEmpty else { return true }
            return a.title.lowercased().contains(query) || (a.authorName?.lowercased().contains(query) ?? false)
                || (a.sectionName?.lowercased().contains(query) ?? false)
        }
    }

    public func load() async {
        guard permissions.isStaff else {
            articles = []
            phase = .failed("Your account has no HCG News newsroom role.")
            return
        }
        phase = .loading
        do {
            async let list = repository.articles()
            async let cats = repository.categories()
            async let people = repository.authors()
            articles = try await list
            sections = (try? await cats) ?? sections
            authors = (try? await people) ?? authors
            if let me = account.user?.id { unsavedArticleIDs = Set(await backups.articleIDs(user: me)) }
            phase = .loaded
        } catch let error as PlatformError {
            phase = .failed(error.message)
            if error == .unauthorized { await account.refreshAccess() }
        } catch {
            phase = .failed("The newsroom couldn't be loaded.")
        }
    }

    /// Creates an empty draft on HCG (owned by this person) and returns an editor for it.
    public func createDraft() async -> RemoteArticleEditorModel? {
        guard permissions.isStaff, let me = account.user?.id else { return nil }
        isCreating = true
        defer { isCreating = false }
        do {
            let article = try await repository.createDraft(userID: me)
            await log?.record(.newsroom, "Created a newsroom draft on HCG")
            await load()
            return editor(for: article)
        } catch let error as PlatformError {
            message = "The draft wasn't created. \(error.message)"
            return nil
        } catch {
            message = "The draft wasn't created."
            return nil
        }
    }

    public func openEditor(id: String) async -> RemoteArticleEditorModel? {
        do {
            let article = try await repository.article(id: id)
            return editor(for: article)
        } catch let error as PlatformError {
            message = error.message
            return nil
        } catch {
            message = "The article couldn't be opened."
            return nil
        }
    }

    func editor(for article: NewsroomArticle) -> RemoteArticleEditorModel {
        RemoteArticleEditorModel(article: article, desk: self)
    }

    func noteBackup(_ id: String, present: Bool) {
        if present { unsavedArticleIDs.insert(id) } else { unsavedArticleIDs.remove(id) }
    }

    func replace(_ article: NewsroomArticle) {
        guard let index = articles.firstIndex(where: { $0.id == article.id }) else { return }
        let old = articles[index]
        articles[index] = NewsroomArticleSummary(
            id: article.id, title: article.fields.title.isEmpty ? "Untitled article" : article.fields.title,
            slug: article.fields.slug, status: article.status, contentType: article.fields.contentType,
            publishedAt: article.publishedAt, updatedAt: article.updatedAt, isFeatured: article.fields.isFeatured,
            isBreaking: article.fields.isBreaking, isDemo: article.isDemo,
            sectionName: sections.first { $0.id == article.fields.categoryID }?.name ?? old.sectionName,
            authorName: authors.first { $0.id == article.fields.authorID }?.name ?? old.authorName, createdBy: article.createdBy)
    }
}

/// Editing one newsroom article. Every change is local until an explicit Save; status
/// changes need an explicit, confirmed action; nothing is retried or queued.
@MainActor
@Observable
public final class RemoteArticleEditorModel: Identifiable {
    public enum Phase: Equatable, Sendable {
        case idle
        case saving
        case saved(Date)
        case failed(String)
        /// Someone else saved first. Local edits are kept; the person chooses what to do.
        case conflict(NewsroomArticle)
    }

    public enum BodyMode: Equatable, Sendable {
        case editable
        case readOnly(String)
    }

    public nonisolated let id: String
    public private(set) var base: NewsroomArticle
    public var fields: NewsroomArticleFields { didSet { scheduleBackup() } }
    public var blocks: [EditableBodyBlock] {
        didSet {
            // An untouched body keeps its original HTML byte for byte.
            if bodyMode == .editable { fields.body = blocks == loadedBlocks ? base.fields.body : ArticleBodyCodec.encode(blocks) }
        }
    }
    public private(set) var bodyMode: BodyMode
    public private(set) var phase: Phase = .idle
    public private(set) var recoverableBackup: RemoteEditBackupStore.Backup?
    public private(set) var versions: [NewsroomVersion] = []
    public private(set) var media: [NewsroomMedia] = []
    public private(set) var isUploading = false
    public private(set) var notice: String?
    public var tagsText: String {
        get { fields.tags.joined(separator: ", ") }
        set { fields.tags = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    }

    @ObservationIgnored public let desk: NewsroomDeskModel
    @ObservationIgnored private var backupTask: Task<Void, Never>?
    /// The body exactly as loaded, so an untouched body is never re-encoded and sent.
    @ObservationIgnored private var loadedBlocks: [EditableBodyBlock]

    init(article: NewsroomArticle, desk: NewsroomDeskModel) {
        id = article.id
        base = article
        self.desk = desk
        fields = article.fields
        let decodedBlocks: [EditableBodyBlock]
        switch ArticleBodyCodec.decode(article.fields.body, publicationURL: desk.publicationURL) {
        case .editable(let decoded):
            decodedBlocks = decoded
            bodyMode = .editable
        case .readOnly(let reason):
            decodedBlocks = []
            bodyMode = .readOnly(reason)
        }
        blocks = decodedBlocks
        loadedBlocks = decodedBlocks
    }

    public var permissions: NewsroomPermissions { desk.permissions }
    public var userID: String? { desk.account.user?.id }
    public var canEdit: Bool { permissions.canEdit(createdBy: base.createdBy, status: base.status, userID: userID) }
    public var hasUnsavedChanges: Bool { fields != base.fields }
    public var sections: [NewsroomCategory] { desk.sections }
    public var authors: [NewsroomAuthor] { desk.authors }
    public var previewURL: URL? {
        guard base.isLive() else { return nil }
        let section = desk.sections.first { $0.id == base.fields.categoryID }?.slug
        return PublicationMapping.canonicalURL(publicationURL: desk.publicationURL, sectionSlug: section, slug: base.fields.slug)
    }

    // MARK: Unsaved-edit protection

    public func checkForBackup() async {
        guard let me = userID, let backup = await desk.backups.load(user: me, article: id) else { return }
        if backup.fields == base.fields { await desk.backups.remove(user: me, article: id); return }
        recoverableBackup = backup
    }

    /// Puts the saved-on-device edits back into the editor (still unsaved on HCG).
    public func recoverBackup() {
        guard let backup = recoverableBackup else { return }
        fields = backup.fields
        if bodyMode == .editable, case .editable(let decoded) = ArticleBodyCodec.decode(backup.fields.body, publicationURL: desk.publicationURL) {
            blocks = decoded
        }
        fields.body = backup.fields.body
        recoverableBackup = nil
        if backup.baseRevision != base.revision {
            notice = "The article changed on HCG after these edits were made. Saving will report a conflict so you can compare."
            base = NewsroomArticle(id: base.id, createdBy: base.createdBy, createdAt: base.createdAt, revision: backup.baseRevision,
                                   updatedAt: base.updatedAt, status: base.status, publishedAt: base.publishedAt,
                                   isDemo: base.isDemo, viewCount: base.viewCount, fields: base.fields)
        }
    }

    public func discardBackup() async {
        recoverableBackup = nil
        if let me = userID { await desk.backups.remove(user: me, article: id); desk.noteBackup(id, present: false) }
    }

    private func scheduleBackup() {
        backupTask?.cancel()
        guard let me = userID else { return }
        let snapshot = RemoteEditBackupStore.Backup(articleID: id, baseRevision: base.revision, fields: fields, savedAt: Date())
        let unchanged = fields == base.fields
        let store = desk.backups
        let articleID = id
        backupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            if unchanged { await store.remove(user: me, article: articleID) } else { await store.save(snapshot, user: me) }
            self?.desk.noteBackup(articleID, present: !unchanged)
        }
    }

    /// Writes the backup immediately (e.g. when the app goes to the background).
    public func flushBackup() async {
        backupTask?.cancel()
        guard let me = userID, hasUnsavedChanges else { return }
        await desk.backups.save(.init(articleID: id, baseRevision: base.revision, fields: fields, savedAt: Date()), user: me)
        desk.noteBackup(id, present: true)
    }

    // MARK: Saving and status

    public var validationProblems: [String] {
        var problems: [String] = []
        if fields.title.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Add a headline.") }
        if fields.slug.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Add a slug.") }
        if bodyMode == .editable { problems += ArticleBodyCodec.problems(blocks) }
        if !fields.featuredImageURL.isEmpty, fields.featuredImageAlt.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("Add alt text for the cover image.")
        }
        return problems
    }

    public func save() async {
        await perform(status: nil, publishedAt: nil, label: "Saved to HCG")
    }

    /// Status changes this person may make now, per the website's rules. The server
    /// authorises each one again.
    public var availableTransitions: [EditorialStatus] {
        guard canEdit else { return [] }
        let allowed = permissions.allowedStatuses
        let current = base.status
        return allowed.filter { status in
            guard status.rawValue != current else { return false }
            if status == .published { return permissions.canPublish(fromStatus: current) }
            return true
        }
    }

    /// Problems blocking publication now.
    public var publicationProblems: [String] {
        var problems = fields.publicationProblems
        if !permissions.canPublish(fromStatus: base.status) {
            problems.append(permissions.canPublish ? "Approval is required before publication." : "Final publication requires an Editor-in-Chief or Administrator.")
        }
        return problems + validationProblems
    }

    /// Moves the article to `status`. For publication, `scheduleAt` nil publishes now;
    /// a date schedules it (it must be in the future).
    public func change(to status: EditorialStatus, scheduleAt: Date? = nil) async {
        if status == .published {
            let problems = publicationProblems
            guard problems.isEmpty else { phase = .failed(problems.joined(separator: " ")); return }
            if let scheduleAt, scheduleAt <= Date() { phase = .failed("Choose a future publication date."); return }
            await perform(status: .published, publishedAt: scheduleAt ?? Date(),
                          label: scheduleAt == nil ? "Published" : "Scheduled")
        } else {
            guard availableTransitions.contains(status) else { phase = .failed("Your role can't set this status."); return }
            await perform(status: status, publishedAt: nil, label: "Status: \(status.title)")
        }
    }

    private func perform(status: EditorialStatus?, publishedAt: Date?, label: String) async {
        guard let me = userID else { phase = .failed("Sign in again to save."); return }
        guard canEdit else { phase = .failed("Your HCG News role doesn't allow editing this article."); return }
        let problems = validationProblems
        guard problems.isEmpty else { phase = .failed(problems.joined(separator: " ")); return }
        if bodyMode == .editable, blocks == loadedBlocks { fields.body = base.fields.body }
        phase = .saving
        do {
            let result = try await desk.repository.save(fields, over: base, status: status, publishedAt: publishedAt, userID: me)
            adopt(result.article)
            phase = .saved(Date())
            notice = status != nil && !result.versionRecorded ? "\(label). The version history entry couldn't be recorded." : label
            await desk.backups.remove(user: me, article: id)
            desk.noteBackup(id, present: false)
            desk.replace(result.article)
            await desk.log?.record(.newsroom, "\(label) (newsroom article)")
        } catch {
            switch error {
            case .conflict(let server):
                phase = .conflict(server)
                await flushBackup()
            case .platform(let platformError):
                phase = .failed("Not saved. \(platformError.message) Your edits are kept on this device.")
                await flushBackup()
                if platformError == .unauthorized { await desk.account.refreshAccess() }
                if case .forbidden = platformError { await desk.account.refreshAccess() }
            }
        }
    }

    private func adopt(_ article: NewsroomArticle) {
        base = article
        fields = article.fields
        if case .editable(let decoded) = ArticleBodyCodec.decode(article.fields.body, publicationURL: desk.publicationURL) {
            blocks = decoded
            bodyMode = .editable
        } else if case .readOnly(let reason) = ArticleBodyCodec.decode(article.fields.body, publicationURL: desk.publicationURL) {
            bodyMode = .readOnly(reason)
        }
        loadedBlocks = blocks
        fields.body = article.fields.body
        backupTask?.cancel()
    }

    // MARK: Conflicts

    /// Keeps these edits and makes the server's latest version the base, so the next
    /// explicit Save replaces the other person's changes to the fields edited here.
    public func keepMineOverServer() {
        guard case .conflict(let server) = phase else { return }
        let mine = fields
        base = server
        fields = mine
        phase = .idle
        notice = "Review your edits, then Save to replace the other changes."
    }

    /// Discards these edits and loads the server's version.
    public func takeServerVersion() async {
        guard case .conflict(let server) = phase else { return }
        adopt(server)
        phase = .idle
        if let me = userID { await desk.backups.remove(user: me, article: id); desk.noteBackup(id, present: false) }
        notice = "Loaded the latest version from HCG."
    }

    /// Reloads from HCG (only when there are no unsaved edits).
    public func reload() async {
        guard !hasUnsavedChanges else { return }
        do { adopt(try await desk.repository.article(id: id)); phase = .idle }
        catch let error as PlatformError { phase = .failed(error.message) }
        catch { phase = .failed("Couldn't reload.") }
    }

    // MARK: Versions

    public func loadVersions() async {
        do { versions = try await desk.repository.versions(articleID: id) }
        catch let error as PlatformError { notice = "Version history unavailable: \(error.message)" }
        catch {}
    }

    /// Copies a version's headline, standfirst and body into the editor. Nothing is
    /// saved until Save is tapped.
    public func restore(_ version: NewsroomVersion) {
        if let t = version.title { fields.title = t }
        fields.subtitle = version.subtitle ?? ""
        if let body = version.body {
            switch ArticleBodyCodec.decode(body, publicationURL: desk.publicationURL) {
            case .editable(let decoded) where bodyMode == .editable:
                blocks = decoded
                fields.body = body
            default:
                fields.body = body
                bodyMode = .readOnly("This restored version's body can't be edited in the app. It will be saved as it was.")
            }
        }
        notice = "Version copied into the editor. Save to keep it."
    }

    // MARK: Media

    public func loadMedia() async {
        do { media = try await desk.repository.media().filter { $0.kind == "image" } }
        catch let error as PlatformError { notice = "Media library unavailable: \(error.message)" }
        catch {}
    }

    public func upload(data: Data, mimeType: String, fileExtension: String, caption: String, altText: String, credit: String) async -> NewsroomMedia? {
        guard let me = userID else { return nil }
        guard !altText.trimmingCharacters(in: .whitespaces).isEmpty else { notice = "Add alt text before uploading."; return nil }
        isUploading = true
        defer { isUploading = false }
        do {
            let item = try await desk.repository.upload(data: data, mimeType: mimeType, fileExtension: fileExtension, articleID: id,
                                                        userID: me, caption: caption, altText: altText, credit: credit)
            media.insert(item, at: 0)
            notice = "Uploaded to the HCG News media library."
            return item
        } catch let error as PlatformError {
            notice = "Upload failed. \(error.message)"
            return nil
        } catch {
            notice = "Upload failed."
            return nil
        }
    }

    public func useAsCover(_ item: NewsroomMedia) {
        guard let url = item.url else { return }
        fields.featuredImageURL = url.absoluteString
        fields.featuredImageAlt = item.altText ?? fields.featuredImageAlt
        fields.featuredImageCaption = item.caption ?? ""
        fields.featuredImageCredit = item.credit ?? ""
    }

    public func insertImage(_ item: NewsroomMedia, at index: Int? = nil) {
        guard bodyMode == .editable, let url = item.url else { return }
        let block = EditableBodyBlock(kind: .image, imageURL: url.absoluteString, altText: item.altText ?? "",
                                      caption: item.caption ?? "", credit: item.credit ?? "")
        if let index, index <= blocks.count { blocks.insert(block, at: index) } else { blocks.append(block) }
    }

    public func clearNotice() { notice = nil }
}

/// Administration for Administrators (audit) and Editors-in-Chief (sections).
@MainActor
@Observable
public final class NewsroomAdminDeskModel {
    public private(set) var audit: [NewsroomAuditEntry] = []
    public private(set) var auditState: String?
    public private(set) var sections: [NewsroomCategory] = []
    public private(set) var message: String?

    @ObservationIgnored let desk: NewsroomDeskModel

    public init(desk: NewsroomDeskModel) { self.desk = desk }

    public var permissions: NewsroomPermissions { desk.permissions }

    public func load() async {
        do { sections = try await desk.repository.categories() } catch let e as PlatformError { message = e.message } catch {}
        guard permissions.canViewAudit else { auditState = "Only HCG News Administrators can see the audit history."; return }
        do { audit = try await desk.repository.audit(); auditState = audit.isEmpty ? "No audit entries were returned." : nil }
        catch let e as PlatformError { auditState = "The audit history couldn't be loaded: \(e.message)" }
        catch {}
    }

    public func addSection(named name: String) async {
        guard permissions.canManageSections else { message = "Your role can't manage sections."; return }
        do {
            let created = try await desk.repository.createCategory(name: name, sortOrder: (sections.compactMap(\.sortOrder).max() ?? 0) + 1)
            sections.append(created)
            message = "Section \"\(created.name)\" added."
            await desk.log?.record(.newsroom, "Section added")
        } catch let e as PlatformError { message = "Not added. \(e.message)" } catch {}
    }

    public func setVisible(_ section: NewsroomCategory, _ visible: Bool) async {
        guard permissions.canManageSections else { return }
        do {
            let updated = try await desk.repository.updateCategory(id: section.id, changes: ["is_visible": visible])
            if let i = sections.firstIndex(where: { $0.id == section.id }) { sections[i] = updated }
        } catch let e as PlatformError { message = "Not changed. \(e.message)" } catch {}
    }

    public func rename(_ section: NewsroomCategory, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard permissions.canManageSections, !trimmed.isEmpty, trimmed != section.name else { return }
        do {
            let updated = try await desk.repository.updateCategory(id: section.id, changes: ["name": trimmed])
            if let i = sections.firstIndex(where: { $0.id == section.id }) { sections[i] = updated }
        } catch let e as PlatformError { message = "Not renamed. \(e.message)" } catch {}
    }
}
