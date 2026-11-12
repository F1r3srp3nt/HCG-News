import Foundation
import Observation
import NewsCore
import Newsroom

/// Inputs the newsroom needs from the account, evaluated at call time.
public struct NewsroomAccess: Sendable {
    public let serviceConfigured: Bool
    public let signedIn: Bool
    public let centralAccessGranted: Bool

    public init(serviceConfigured: Bool, signedIn: Bool, centralAccessGranted: Bool) {
        self.serviceConfigured = serviceConfigured
        self.signedIn = signedIn
        self.centralAccessGranted = centralAccessGranted
    }
}

/// A revision conflict: the server has a newer version. Nothing was overwritten.
public struct DraftConflict: Equatable, Sendable, Identifiable {
    public let draftID: UUID
    public let server: ServerDraftSummary
    public var id: UUID { draftID }
}

/// Outcome of a remote action, shown to the user.
public enum RemoteOutcome: Equatable, Sendable {
    case succeeded(String)
    case failed(String)
}

@MainActor
@Observable
public final class NewsroomModel {
    public private(set) var drafts: [Draft] = []
    public private(set) var recoveries: [Draft] = []
    public var filter = DraftFilter()
    public private(set) var capabilities: NewsroomCapabilities?
    public private(set) var capabilitiesError: String?
    public private(set) var isWorking = false
    public private(set) var conflict: DraftConflict?
    public private(set) var lastOutcome: RemoteOutcome?

    public let store: DraftStore
    private let service: NewsroomService
    private let access: () -> NewsroomAccess
    private let environment: String
    private let generator: String
    private let log: LocalEventLog?

    public init(store: DraftStore, service: NewsroomService, environment: String, generator: String,
                log: LocalEventLog? = nil, access: @escaping () -> NewsroomAccess) {
        self.store = store
        self.service = service
        self.environment = environment
        self.generator = generator
        self.log = log
        self.access = access
    }

    public var filteredDrafts: [Draft] { drafts.filter(filter.matches) }

    public func reload() async {
        drafts = await store.all()
        recoveries = await store.pendingRecoveries()
    }

    public func create() async -> Draft? {
        let draft = try? await store.create()
        await reload()
        return draft
    }

    public func delete(_ id: UUID) async {
        await store.delete(id)
        await log?.record(.newsroom, "Local draft deleted")
        await reload()
    }

    public func recover(_ id: UUID) async {
        _ = try? await store.recover(id)
        await log?.record(.newsroom, "Recovered unsaved draft changes")
        await reload()
    }

    public func discardRecovery(_ id: UUID) async {
        await store.discardRecovery(id)
        await reload()
    }

    // MARK: Export / import

    public func export(_ id: UUID) async throws -> Data {
        try await store.export(id, generator: generator)
    }

    public func importDraft(_ data: Data) async throws -> Draft {
        let draft = try await store.importDraft(data)
        await log?.record(.newsroom, "Imported a draft file as a new local draft")
        await reload()
        return draft
    }

    // MARK: Remote availability

    public func availability(_ action: NewsroomAction) -> ActionAvailability {
        let a = access()
        return NewsroomGate.availability(action, serviceConfigured: a.serviceConfigured, signedIn: a.signedIn,
                                         centralAccessGranted: a.centralAccessGranted, capabilities: capabilities)
    }

    public func loadCapabilities() async {
        let a = access()
        guard a.serviceConfigured, a.signedIn, a.centralAccessGranted else { capabilities = nil; return }
        do {
            capabilities = try await service.capabilities()
            capabilitiesError = nil
        } catch {
            capabilities = nil
            capabilitiesError = Self.describe(error)
        }
    }

    // MARK: Remote actions (explicit, never queued)

    /// Creates or updates the server draft. Only on an explicit tap; when offline,
    /// it fails and nothing is retried later.
    public func saveToNewsroom(_ id: UUID) async {
        guard availability(.saveDraft).isAvailable, var draft = await store.draft(id) else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            // Upload media first when supported and needed.
            var remoteIDs: [UUID: String] = [:]
            for attachment in draft.attachments {
                if case .uploaded(let remote) = attachment.uploadState { remoteIDs[attachment.id] = remote; continue }
                guard availability(.uploadMedia).isAvailable,
                      let url = await store.attachmentURL(draft: id, attachment: attachment.id),
                      let data = try? Data(contentsOf: url) else { continue }
                await store.setUploadState(draft: id, attachment: attachment.id, state: .uploading)
                do {
                    let remote = try await service.uploadMedia(data: data, filename: attachment.filename, mimeType: attachment.mimeType)
                    await store.setUploadState(draft: id, attachment: attachment.id, state: .uploaded(remoteID: remote))
                    remoteIDs[attachment.id] = remote
                } catch {
                    await store.setUploadState(draft: id, attachment: attachment.id, state: .failed(reason: Self.describe(error)))
                }
            }
            draft = await store.draft(id) ?? draft
            let summary = try await service.saveDraft(draft, mediaRemoteIDs: remoteIDs)
            _ = try await store.link(id, to: ServerLink(serverDraftID: summary.id, serverRevision: summary.revision,
                                                       remoteStatus: summary.status, lastSyncedAt: Date(), environment: environment))
            lastOutcome = .succeeded("Saved to the newsroom as revision \(summary.revision). It has not been submitted or published.")
            await log?.record(.newsroom, "Draft saved to newsroom (status \(summary.status))")
        } catch NewsroomError.conflict(let server) {
            conflict = DraftConflict(draftID: id, server: server)
            lastOutcome = .failed("The newsroom has a newer version. Nothing was overwritten.")
        } catch {
            lastOutcome = .failed(Self.describe(error))
        }
        await reload()
    }

    /// Runs an editorial action on the linked server draft. Destructive actions
    /// must be confirmed by the UI after showing the affected article.
    public func perform(_ action: NewsroomAction, draftID: UUID, scheduleAt: Date? = nil, note: String? = nil) async {
        guard availability(action).isAvailable, let draft = await store.draft(draftID), let link = draft.serverLink else {
            lastOutcome = .failed("This action needs a newsroom draft. Save to the newsroom first.")
            return
        }
        if draft.hasUnsyncedChanges {
            lastOutcome = .failed("Your latest local changes aren't in the newsroom yet. Save to the newsroom first, so the action applies to what you see.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let summary = try await service.perform(action, serverID: link.serverDraftID, baseRevision: link.serverRevision,
                                                    scheduleAt: scheduleAt, note: note)
            _ = try await store.link(draftID, to: ServerLink(serverDraftID: summary.id, serverRevision: summary.revision,
                                                            remoteStatus: summary.status, lastSyncedAt: Date(), environment: environment))
            lastOutcome = .succeeded("\(action.title): the newsroom reports status “\(summary.status)”.")
            await log?.record(.newsroom, "\(action.title) accepted by the newsroom (status \(summary.status))")
        } catch NewsroomError.conflict(let server) {
            conflict = DraftConflict(draftID: draftID, server: server)
            lastOutcome = .failed("The newsroom has a newer version. Nothing was changed.")
        } catch {
            lastOutcome = .failed(Self.describe(error))
            await log?.record(.newsroom, "\(action.title) refused or failed")
        }
        await reload()
    }

    // MARK: Conflict resolution (explicit)

    /// Keeps the local text as a separate, unlinked local draft. The server version is untouched.
    public func resolveConflictKeepingMineAsCopy() async {
        guard let conflict, let draft = await store.draft(conflict.draftID) else { return }
        _ = try? await store.duplicate(draft)
        self.conflict = nil
        lastOutcome = .succeeded("Your version was kept as a separate local draft.")
        await reload()
    }

    /// Replaces the local draft with the server's version (a snapshot of the local one is kept).
    public func resolveConflictLoadingServerVersion() async {
        guard let conflict, let local = await store.draft(conflict.draftID) else { return }
        do {
            let server = try await service.fetchDraft(serverID: conflict.server.id)
            try await store.snapshot(local, reason: "Before loading the newsroom version")
            var replacement = server.draft
            replacement.serverLink = ServerLink(serverDraftID: server.summary.id, serverRevision: server.summary.revision,
                                                remoteStatus: server.summary.status, lastSyncedAt: Date(), environment: environment)
            let rebuilt = Draft.replacing(local, with: replacement)
            _ = try await store.save(rebuilt)
            _ = try await store.link(local.id, to: replacement.serverLink!)
            self.conflict = nil
            lastOutcome = .succeeded("Loaded the newsroom version. Your previous text is kept as a snapshot.")
        } catch {
            lastOutcome = .failed(Self.describe(error))
        }
        await reload()
    }

    public func dismissConflict() { conflict = nil }
    public func clearOutcome() { lastOutcome = nil }

    static func describe(_ error: Error) -> String {
        switch error {
        case NewsroomError.notConfigured: "The newsroom service isn't available."
        case NewsroomError.notSignedIn: "Sign in with HCG Connect first."
        case NewsroomError.unsupported(let a): "The newsroom doesn't support “\(a.title)”."
        case NewsroomError.denied(let message): message ?? "The newsroom refused this action for your account."
        case NewsroomError.offline: "You're offline. Nothing was sent, and nothing will be sent automatically later."
        case NewsroomError.validation(let problems): problems.isEmpty ? "The newsroom rejected the draft." : problems.joined(separator: " ")
        case NewsroomError.server(let code): "The newsroom answered with an error (\(code))."
        case NewsroomError.contract(let message): message
        case NewsroomError.conflict: "The newsroom has a newer version."
        default: "The action failed."
        }
    }
}

extension Draft {
    /// The local draft's identity with another draft's content.
    static func replacing(_ local: Draft, with other: Draft) -> Draft {
        var result = local
        result.headline = other.headline
        result.standfirst = other.standfirst
        result.blocks = other.blocks
        result.sectionSlug = other.sectionSlug
        result.sectionName = other.sectionName
        result.editorialTypeWire = other.editorialTypeWire
        result.authors = other.authors
        result.cover = other.cover
        result.serverLink = other.serverLink
        return result
    }
}

// MARK: - Editor

@MainActor
@Observable
public final class DraftEditorModel {
    public var draft: Draft {
        didSet { if draft != oldValue, !isReloading { isDirty = true; scheduleAutosave() } }
    }
    @ObservationIgnored private var isReloading = false
    public private(set) var isDirty = false
    public private(set) var lastSavedAt: Date?
    public private(set) var snapshots: [DraftSnapshot] = []
    public private(set) var error: String?

    private let store: DraftStore
    private var autosaveTask: Task<Void, Never>?
    private let autosaveDelay: Duration

    public init(draft: Draft, store: DraftStore, autosaveDelay: Duration = .seconds(2)) {
        self.draft = draft
        self.store = store
        self.autosaveDelay = autosaveDelay
        self.lastSavedAt = draft.updatedAt
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let snapshot = draft
        let delay = autosaveDelay
        autosaveTask = Task { [store] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await store.autosave(snapshot)
        }
    }

    /// Replaces the edited draft with a version just read from the store (e.g. after a
    /// newsroom action updated its link). Not an edit: nothing becomes dirty or autosaved.
    public func reload(from stored: Draft) {
        autosaveTask?.cancel()
        isReloading = true
        draft = stored
        isReloading = false
        isDirty = false
        lastSavedAt = stored.updatedAt
    }

    /// Writes the autosave immediately (e.g. when the app moves to the background).
    public func flushAutosave() async {
        autosaveTask?.cancel()
        if isDirty { await store.autosave(draft) }
    }

    /// Explicit local save. Never submits or publishes.
    public func save() async {
        autosaveTask?.cancel()
        do {
            draft = try await store.save(draft)
            isDirty = false
            lastSavedAt = draft.updatedAt
            error = nil
        } catch {
            self.error = "The draft couldn't be saved on this device."
        }
        await loadSnapshots()
    }

    public func takeSnapshot() async {
        await save()
        try? await store.snapshot(draft, reason: "Saved by you")
        await loadSnapshots()
    }

    public func loadSnapshots() async {
        snapshots = await store.snapshots(draft.id)
    }

    public func restore(_ snapshot: DraftSnapshot) async {
        do {
            draft = try await store.restore(draft.id, snapshot: snapshot.id)
            isDirty = false
            lastSavedAt = draft.updatedAt
        } catch {
            self.error = "That version couldn't be restored."
        }
        await loadSnapshots()
    }

    // MARK: Blocks

    public func addBlock(_ kind: DraftBlockKind, after id: UUID? = nil) {
        let block = DraftBlock(kind: kind, image: kind == .image ? DraftImageMeta() : nil)
        if let id, let index = draft.blocks.firstIndex(where: { $0.id == id }) {
            draft.blocks.insert(block, at: index + 1)
        } else {
            draft.blocks.append(block)
        }
    }

    public func removeBlock(_ id: UUID) {
        draft.blocks.removeAll { $0.id == id }
        if draft.blocks.isEmpty { draft.blocks = [DraftBlock(kind: .paragraph)] }
    }

    public func moveBlock(_ id: UUID, by offset: Int) {
        guard let index = draft.blocks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard draft.blocks.indices.contains(target) else { return }
        draft.blocks.swapAt(index, target)
    }

    // MARK: Media

    public func attach(data: Data, filename: String, mimeType: String) async -> MediaAttachment? {
        do {
            let attachment = try await store.addAttachment(to: draft.id, data: data, filename: filename, mimeType: mimeType)
            draft.attachments.append(attachment)
            error = nil
            return attachment
        } catch DraftStoreError.attachmentTooLarge(let limit) {
            error = "That file is larger than \(limit / 1024 / 1024) MB."
        } catch DraftStoreError.unsupportedMediaType {
            error = "Only JPEG, PNG, HEIC, WebP and GIF images can be attached."
        } catch {
            self.error = "The file couldn't be attached."
        }
        return nil
    }

    public func removeAttachment(_ id: UUID) async {
        draft.attachments.removeAll { $0.id == id }
        if draft.cover?.attachmentID == id { draft.cover?.attachmentID = nil }
        for index in draft.blocks.indices where draft.blocks[index].image?.attachmentID == id {
            draft.blocks[index].image?.attachmentID = nil
        }
        await store.removeAttachmentFile(draft: draft.id, attachment: id)
    }

    public func previewArticle() async -> Article {
        var urls: [UUID: URL] = [:]
        for attachment in draft.attachments {
            urls[attachment.id] = await store.attachmentURL(draft: draft.id, attachment: attachment.id)
        }
        return DraftMarkup.previewArticle(draft) { urls[$0] }
    }
}

// MARK: - Administration

@MainActor
@Observable
public final class AdminModel {
    public private(set) var queue: LoadState<[ServerDraftSummary]> = .idle
    public private(set) var audit: LoadState<[AuditEntry]> = .idle
    public private(set) var localEvents: [LocalEvent] = []
    public private(set) var queueUnavailable: String?
    public private(set) var auditUnavailable: String?

    private let newsroom: NewsroomModel
    private let service: NewsroomService
    private let log: LocalEventLog?

    public init(newsroom: NewsroomModel, service: NewsroomService, log: LocalEventLog?) {
        self.newsroom = newsroom
        self.service = service
        self.log = log
    }

    public func reload() async {
        localEvents = await log?.all() ?? []
        await newsroom.loadCapabilities()
        let queueAvailability = newsroom.availability(.viewQueue)
        queueUnavailable = queueAvailability.reason
        if queueAvailability.isAvailable {
            queue = .loading
            do { queue = .loaded(try await service.queue()) } catch {
                queue = .idle
                queueUnavailable = NewsroomModel.describe(error)
            }
        }
        let auditAvailability = newsroom.availability(.viewAudit)
        auditUnavailable = auditAvailability.reason
        if auditAvailability.isAvailable {
            audit = .loading
            do { audit = .loaded(try await service.audit(serverID: nil)) } catch {
                audit = .idle
                auditUnavailable = NewsroomModel.describe(error)
            }
        }
    }

    public func clearLocalEvents() async {
        await log?.clear()
        localEvents = []
    }
}
