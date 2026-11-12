import Foundation
import HCGTransport

public struct DraftSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: Date
    public let reason: String
    public let headline: String
    public let localRevision: Int
}

public enum DraftStoreError: Error, Equatable, Sendable {
    case notFound
    case writeFailed
    case attachmentTooLarge(limitBytes: Int)
    case unsupportedMediaType(String)
    case invalidExport(String)
    case unsupportedExportVersion(Int)
}

/// Exported draft file (format `hcg-news-draft`, version 1). See docs/NEWSROOM-DRAFT-FORMAT.md.
public struct DraftExport: Codable, Equatable, Sendable {
    public struct Media: Codable, Equatable, Sendable {
        public let id: UUID
        public let filename: String
        public let mimeType: String
        /// Base64-encoded file contents.
        public let data: String
    }

    public static let formatName = "hcg-news-draft"
    public static let currentVersion = 1

    public let format: String
    public let version: Int
    public let exportedAt: Date
    public let generator: String
    /// The draft without any server link (an export is never a submission).
    public let draft: Draft
    public let media: [Media]
}

/// Local drafts on this device.
///
/// Layout: `<root>/<draftID>/draft.json` (last explicit save), `autosave.json`
/// (written frequently while editing), `revisions/<n>.json` (snapshots) and
/// `media/<attachmentID>`.
public actor DraftStore {
    public static let maxSnapshots = 30
    public static let attachmentLimitBytes = 25 * 1024 * 1024
    public static let allowedMediaTypes: Set<String> = ["image/jpeg", "image/png", "image/heic", "image/webp", "image/gif"]

    private let root: URL
    private let now: @Sendable () -> Date

    public init(root: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root
        self.now = now
    }

    public static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("HCGNews/Newsroom/Drafts", isDirectory: true)
    }

    // MARK: Paths

    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func draftFile(_ id: UUID) -> URL { folder(id).appendingPathComponent("draft.json") }
    private func autosaveFile(_ id: UUID) -> URL { folder(id).appendingPathComponent("autosave.json") }
    private func revisionsFolder(_ id: UUID) -> URL { folder(id).appendingPathComponent("revisions", isDirectory: true) }
    private func mediaFolder(_ id: UUID) -> URL { folder(id).appendingPathComponent("media", isDirectory: true) }

    public func attachmentURL(draft: UUID, attachment: UUID) -> URL? {
        let url = mediaFolder(draft).appendingPathComponent(attachment.uuidString)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Reading

    /// All saved drafts, most recently updated first.
    public func all() -> [Draft] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return ids.compactMap(UUID.init(uuidString:)).compactMap(read).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func draft(_ id: UUID) -> Draft? { read(id) }

    public func search(_ filter: DraftFilter) -> [Draft] { all().filter(filter.matches) }

    private func read(_ id: UUID) -> Draft? {
        guard let data = try? Data(contentsOf: draftFile(id)) else { return nil }
        return try? HCGJSON.makeDecoder().decode(Draft.self, from: data)
    }

    private func readAutosave(_ id: UUID) -> Draft? {
        guard let data = try? Data(contentsOf: autosaveFile(id)) else { return nil }
        return try? HCGJSON.makeDecoder().decode(Draft.self, from: data)
    }

    // MARK: Writing

    public func create() throws -> Draft {
        let draft = Draft(now: now())
        try write(draft, to: draftFile(draft.id))
        return draft
    }

    /// Explicit save. Clears the autosave and takes a snapshot when the last one is
    /// older than five minutes. Returns the saved draft (revision incremented).
    @discardableResult
    public func save(_ draft: Draft) throws -> Draft {
        var saved = draft
        saved.updatedAt = now()
        saved.localRevision += 1
        try write(saved, to: draftFile(saved.id))
        try? FileManager.default.removeItem(at: autosaveFile(saved.id))
        let last = snapshots(saved.id).first?.createdAt ?? .distantPast
        if now().timeIntervalSince(last) > 300 {
            try? snapshot(saved, reason: "Automatic")
        }
        return saved
    }

    /// Frequent, cheap crash protection while editing. Never replaces the saved draft.
    public func autosave(_ draft: Draft) {
        var copy = draft
        copy.updatedAt = now()
        try? write(copy, to: autosaveFile(draft.id))
    }

    /// Drafts whose autosave is newer than the last save (e.g. after a crash).
    public func pendingRecoveries() -> [Draft] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: root.path))?.compactMap(UUID.init(uuidString:)) ?? []
        return ids.compactMap { id -> Draft? in
            guard let auto = readAutosave(id) else { return nil }
            if let saved = read(id), saved.updatedAt >= auto.updatedAt { return nil }
            return auto
        }
    }

    /// Keeps the recovered text as the saved draft.
    @discardableResult
    public func recover(_ id: UUID) throws -> Draft {
        guard let auto = readAutosave(id) else { throw DraftStoreError.notFound }
        if let saved = read(id) { try? snapshot(saved, reason: "Before recovery") }
        return try save(auto)
    }

    public func discardRecovery(_ id: UUID) {
        try? FileManager.default.removeItem(at: autosaveFile(id))
        // A draft that was never explicitly saved disappears with its autosave.
        if read(id) == nil { try? FileManager.default.removeItem(at: folder(id)) }
    }

    public func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(id))
    }

    /// Creates an unlinked local copy (used to resolve revision conflicts).
    public func duplicate(_ draft: Draft, titleSuffix: String = " (my version)") throws -> Draft {
        var copy = Draft(now: now())
        copy.headline = draft.headline + titleSuffix
        copy.standfirst = draft.standfirst
        copy.blocks = draft.blocks
        copy.sectionSlug = draft.sectionSlug
        copy.sectionName = draft.sectionName
        copy.editorialTypeWire = draft.editorialTypeWire
        copy.authors = draft.authors
        copy.cover = draft.cover
        copy.attachments = draft.attachments.map { var a = $0; a.uploadState = .localOnly; return a }
        try FileManager.default.createDirectory(at: mediaFolder(copy.id), withIntermediateDirectories: true)
        for attachment in draft.attachments {
            if let src = attachmentURL(draft: draft.id, attachment: attachment.id) {
                try? FileManager.default.copyItem(at: src, to: mediaFolder(copy.id).appendingPathComponent(attachment.id.uuidString))
            }
        }
        try write(copy, to: draftFile(copy.id))
        return copy
    }

    // MARK: Snapshots

    public func snapshot(_ draft: Draft, reason: String) throws {
        let folder = revisionsFolder(draft.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = now()
        let name = String(format: "%013.0f", stamp.timeIntervalSince1970 * 1000) + "-" + String(draft.localRevision)
        let record = SnapshotRecord(snapshot: DraftSnapshot(id: name, createdAt: stamp, reason: reason,
                                                            headline: draft.displayTitle, localRevision: draft.localRevision),
                                    draft: draft)
        try write(record, to: folder.appendingPathComponent(name + ".json"))
        let all = snapshots(draft.id)
        for old in all.dropFirst(Self.maxSnapshots) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(old.id + ".json"))
        }
    }

    /// Snapshots, newest first.
    public func snapshots(_ id: UUID) -> [DraftSnapshot] {
        let folder = revisionsFolder(id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { name -> DraftSnapshot? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let record = try? HCGJSON.makeDecoder().decode(SnapshotRecord.self, from: data) else { return nil }
            return record.snapshot
        }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Restores a snapshot. The current version is snapshotted first, so restoring is reversible.
    @discardableResult
    public func restore(_ id: UUID, snapshot snapshotID: String) throws -> Draft {
        let file = revisionsFolder(id).appendingPathComponent(snapshotID + ".json")
        guard let data = try? Data(contentsOf: file),
              let record = try? HCGJSON.makeDecoder().decode(SnapshotRecord.self, from: data) else { throw DraftStoreError.notFound }
        if let current = read(id) { try snapshot(current, reason: "Before restoring an earlier version") }
        var restored = record.draft
        // Keep the current server link and revision counter: restoring is a local edit.
        if let current = read(id) {
            restored.serverLink = current.serverLink
            restored.localRevision = current.localRevision
        }
        return try save(restored)
    }

    struct SnapshotRecord: Codable {
        let snapshot: DraftSnapshot
        let draft: Draft
    }

    // MARK: Attachments

    public func addAttachment(to draftID: UUID, data: Data, filename: String, mimeType: String) throws -> MediaAttachment {
        guard Self.allowedMediaTypes.contains(mimeType.lowercased()) else { throw DraftStoreError.unsupportedMediaType(mimeType) }
        guard data.count <= Self.attachmentLimitBytes else { throw DraftStoreError.attachmentTooLarge(limitBytes: Self.attachmentLimitBytes) }
        let attachment = MediaAttachment(filename: filename, mimeType: mimeType.lowercased(), byteCount: data.count, addedAt: now())
        do {
            try FileManager.default.createDirectory(at: mediaFolder(draftID), withIntermediateDirectories: true)
            try data.write(to: mediaFolder(draftID).appendingPathComponent(attachment.id.uuidString), options: [.atomic])
        } catch {
            throw DraftStoreError.writeFailed
        }
        return attachment
    }

    public func removeAttachmentFile(draft: UUID, attachment: UUID) {
        try? FileManager.default.removeItem(at: mediaFolder(draft).appendingPathComponent(attachment.uuidString))
    }

    // MARK: Server links

    /// Removes every server link (e.g. after the HCG Connect identity configuration
    /// changed). The local text and media are kept.
    public func detachAllServerLinks(note: String) {
        for var draft in all() where draft.serverLink != nil {
            draft.serverLink = nil
            draft.detachedNote = note
            draft.attachments = draft.attachments.map { var a = $0; if case .uploaded = a.uploadState { a.uploadState = .localOnly }; return a }
            try? write(draft, to: draftFile(draft.id))
        }
    }

    /// Records a successful server call. Only called after the server confirmed it.
    public func link(_ id: UUID, to link: ServerLink) throws -> Draft {
        guard var draft = read(id) else { throw DraftStoreError.notFound }
        draft.serverLink = link
        draft.detachedNote = nil
        // `updatedAt` must not exceed lastSyncedAt for a just-synced draft.
        draft.updatedAt = min(draft.updatedAt, link.lastSyncedAt)
        try write(draft, to: draftFile(id))
        return draft
    }

    public func setUploadState(draft id: UUID, attachment: UUID, state: UploadState) {
        guard var draft = read(id), let index = draft.attachments.firstIndex(where: { $0.id == attachment }) else { return }
        draft.attachments[index].uploadState = state
        try? write(draft, to: draftFile(id))
    }

    // MARK: Export / import

    public func export(_ id: UUID, generator: String) throws -> Data {
        guard var draft = read(id) else { throw DraftStoreError.notFound }
        draft.serverLink = nil
        draft.detachedNote = nil
        let media: [DraftExport.Media] = draft.attachments.compactMap { attachment in
            guard let url = attachmentURL(draft: id, attachment: attachment.id), let data = try? Data(contentsOf: url) else { return nil }
            return DraftExport.Media(id: attachment.id, filename: attachment.filename, mimeType: attachment.mimeType,
                                     data: data.base64EncodedString())
        }
        draft.attachments = draft.attachments.map { var a = $0; a.uploadState = .localOnly; return a }
        let export = DraftExport(format: DraftExport.formatName, version: DraftExport.currentVersion, exportedAt: now(),
                                 generator: generator, draft: draft, media: media)
        let encoder = HCGJSON.makeEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(export)
    }

    /// Imports an exported draft as a NEW local draft (new id, no server link).
    public func importDraft(_ data: Data) throws -> Draft {
        guard data.count <= 200 * 1024 * 1024 else { throw DraftStoreError.invalidExport("The file is too large.") }
        struct Header: Decodable { let format: String?; let version: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == DraftExport.formatName else {
            throw DraftStoreError.invalidExport("This is not an HCG News draft file.")
        }
        guard let version = header.version, version <= DraftExport.currentVersion else {
            throw DraftStoreError.unsupportedExportVersion(header.version ?? 0)
        }
        let export: DraftExport
        do { export = try HCGJSON.makeDecoder().decode(DraftExport.self, from: data) } catch {
            throw DraftStoreError.invalidExport("The draft file is damaged or incomplete.")
        }
        var draft = Draft(now: now())
        draft.headline = export.draft.headline
        draft.standfirst = export.draft.standfirst
        draft.blocks = export.draft.blocks
        draft.sectionSlug = export.draft.sectionSlug
        draft.sectionName = export.draft.sectionName
        draft.editorialTypeWire = export.draft.editorialTypeWire
        draft.authors = export.draft.authors
        draft.cover = export.draft.cover

        // Re-key media so imported ids can never collide with existing ones.
        var idMap: [UUID: UUID] = [:]
        try FileManager.default.createDirectory(at: mediaFolder(draft.id), withIntermediateDirectories: true)
        for media in export.media {
            guard Self.allowedMediaTypes.contains(media.mimeType.lowercased()),
                  let bytes = Data(base64Encoded: media.data), bytes.count <= Self.attachmentLimitBytes else { continue }
            let attachment = MediaAttachment(filename: media.filename, mimeType: media.mimeType.lowercased(),
                                             byteCount: bytes.count, addedAt: now())
            try bytes.write(to: mediaFolder(draft.id).appendingPathComponent(attachment.id.uuidString))
            idMap[media.id] = attachment.id
            draft.attachments.append(attachment)
        }
        func remap(_ meta: DraftImageMeta?) -> DraftImageMeta? {
            guard var meta else { return nil }
            meta.attachmentID = meta.attachmentID.flatMap { idMap[$0] }
            return meta
        }
        draft.cover = remap(draft.cover)
        draft.blocks = draft.blocks.map { var b = $0; b.id = UUID(); b.image = remap(b.image); return b }
        try write(draft, to: draftFile(draft.id))
        return draft
    }

    // MARK: Internals

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try HCGJSON.makeEncoder().encode(value)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: [.atomic])
            #endif
        } catch {
            throw DraftStoreError.writeFailed
        }
    }
}
