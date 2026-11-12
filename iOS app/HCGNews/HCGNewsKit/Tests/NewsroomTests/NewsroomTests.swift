import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import HCGTestSupport
import NewsCore
@testable import Newsroom

// Fixture-based tests: local files in a temp folder, fake transport. No live newsroom exists.

final class DraftStoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("drafts-\(UUID().uuidString)") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_800_000_000)
        func now() -> Date { lock.withLock { value } }
        func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
    }

    func testSaveAutosaveAndRecoveryAfterInterruption() async throws {
        let clock = Clock()
        let store = DraftStore(root: root, now: { clock.now() })
        var draft = try await store.create()
        draft.headline = "Saved headline"
        draft = try await store.save(draft)
        XCTAssertEqual(draft.localRevision, 1)

        clock.advance(10)
        var edited = draft
        edited.headline = "Unsaved edit before a crash"
        await store.autosave(edited)

        // "Relaunch": a fresh store sees the newer autosave.
        let relaunched = DraftStore(root: root, now: { clock.now() })
        let pending = await relaunched.pendingRecoveries()
        XCTAssertEqual(pending.map(\.headline), ["Unsaved edit before a crash"])
        let recovered = try await relaunched.recover(draft.id)
        XCTAssertEqual(recovered.headline, "Unsaved edit before a crash")
        let none = await relaunched.pendingRecoveries()
        XCTAssertTrue(none.isEmpty)
    }

    func testDiscardRecoveryKeepsSavedVersion() async throws {
        let clock = Clock()
        let store = DraftStore(root: root, now: { clock.now() })
        var draft = try await store.create()
        draft.headline = "Kept"
        draft = try await store.save(draft)
        clock.advance(5)
        var edit = draft
        edit.headline = "Thrown away"
        await store.autosave(edit)
        await store.discardRecovery(draft.id)
        let reloaded = await store.draft(draft.id)
        XCTAssertEqual(reloaded?.headline, "Kept")
    }

    func testSnapshotsAndReversibleRestore() async throws {
        let clock = Clock()
        let store = DraftStore(root: root, now: { clock.now() })
        var draft = try await store.create()
        draft.headline = "Version one"
        draft = try await store.save(draft)          // automatic snapshot (first save)
        clock.advance(60)
        draft.headline = "Version two"
        draft = try await store.save(draft)          // within 5 min: no automatic snapshot
        let snaps = await store.snapshots(draft.id)
        XCTAssertEqual(snaps.map(\.headline), ["Version one"])

        clock.advance(60)
        let restored = try await store.restore(draft.id, snapshot: snaps[0].id)
        XCTAssertEqual(restored.headline, "Version one")
        let after = await store.snapshots(draft.id)
        XCTAssertEqual(after.first?.headline, "Version two", "restoring snapshots the current version first")
    }

    func testExportImportRoundTripDropsServerLinkAndRekeysMedia() async throws {
        let store = DraftStore(root: root)
        var draft = try await store.create()
        let attachment = try await store.addAttachment(to: draft.id, data: Data([9, 9, 9]), filename: "photo.jpg", mimeType: "image/jpeg")
        draft.attachments = [attachment]
        draft.headline = "Exported"
        draft.cover = DraftImageMeta(attachmentID: attachment.id, caption: "Cap", credit: "Cred", altText: "Alt")
        draft.blocks = [DraftBlock(kind: .paragraph, text: "Body **bold**")]
        draft = try await store.save(draft)
        draft = try await store.link(draft.id, to: ServerLink(serverDraftID: "srv-1", serverRevision: "3", remoteStatus: "draft",
                                                              lastSyncedAt: Date(), environment: "test"))

        let data = try await store.export(draft.id, generator: "tests")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"format\" : \"hcg-news-draft\""))
        XCTAssertFalse(text.contains("srv-1"), "an export never carries the server link")

        let imported = try await store.importDraft(data)
        XCTAssertNotEqual(imported.id, draft.id)
        XCTAssertNil(imported.serverLink)
        XCTAssertEqual(imported.headline, "Exported")
        XCTAssertEqual(imported.attachments.count, 1)
        XCTAssertNotEqual(imported.attachments[0].id, attachment.id)
        XCTAssertEqual(imported.cover?.attachmentID, imported.attachments[0].id)
        let url = await store.attachmentURL(draft: imported.id, attachment: imported.attachments[0].id)
        XCTAssertEqual(try Data(contentsOf: url!), Data([9, 9, 9]))
    }

    func testImportRejectsOtherFilesAndNewerVersions() async {
        let store = DraftStore(root: root)
        do { _ = try await store.importDraft(Data(#"{"hello":1}"#.utf8)); XCTFail() } catch {
            XCTAssertEqual(error as? DraftStoreError, .invalidExport("This is not an HCG News draft file."))
        }
        do { _ = try await store.importDraft(Data(#"{"format":"hcg-news-draft","version":7}"#.utf8)); XCTFail() } catch {
            XCTAssertEqual(error as? DraftStoreError, .unsupportedExportVersion(7))
        }
    }

    func testAttachmentLimits() async throws {
        let store = DraftStore(root: root)
        let draft = try await store.create()
        do { _ = try await store.addAttachment(to: draft.id, data: Data([1]), filename: "x.svg", mimeType: "image/svg+xml"); XCTFail() } catch {
            XCTAssertEqual(error as? DraftStoreError, .unsupportedMediaType("image/svg+xml"))
        }
    }

    func testDetachingServerLinksKeepsText() async throws {
        let store = DraftStore(root: root)
        var draft = try await store.create()
        draft.headline = "Keep me"
        draft = try await store.save(draft)
        _ = try await store.link(draft.id, to: ServerLink(serverDraftID: "s", serverRevision: "1", remoteStatus: "draft", lastSyncedAt: Date(), environment: "a"))
        await store.detachAllServerLinks(note: "Changed")
        let after = await store.draft(draft.id)
        XCTAssertNil(after?.serverLink)
        XCTAssertEqual(after?.headline, "Keep me")
        XCTAssertEqual(after?.detachedNote, "Changed")
    }
}

final class DraftModelTests: XCTestCase {
    func testStateLabelAlwaysSaysLocalDraft() {
        var draft = Draft(now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(draft.stateLabel, "Local draft")
        draft.serverLink = ServerLink(serverDraftID: "s", serverRevision: "1", remoteStatus: "in_review", lastSyncedAt: Date(timeIntervalSince1970: 200), environment: "t")
        XCTAssertTrue(draft.stateLabel.hasPrefix("Local draft"))
        XCTAssertTrue(draft.stateLabel.contains("in review"))
    }

    func testSubmissionProblems() {
        var draft = Draft(now: Date())
        XCTAssertEqual(draft.submissionProblems.count, 4)
        draft.headline = "H"; draft.sectionSlug = "markets"; draft.editorialTypeWire = "news"
        draft.blocks = [DraftBlock(kind: .paragraph, text: "Body"), DraftBlock(kind: .image, image: DraftImageMeta(attachmentID: UUID()))]
        XCTAssertEqual(draft.submissionProblems, ["Add alt text to every image."])
    }

    func testMarkupAndPreview() {
        let inline = DraftMarkup.inline("A **bold** and *italic* [link](https://example.org) [bad](javascript:alert(1))")
        XCTAssertTrue(inline.runs.contains { $0.text == "bold" && $0.bold })
        XCTAssertTrue(inline.runs.contains { $0.text == "italic" && $0.italic })
        XCTAssertEqual(inline.links.map(\.absoluteString), ["https://example.org"])
        XCTAssertEqual(inline.plainText, "A bold and italic link bad")

        var draft = Draft(now: Date())
        draft.headline = "Preview"
        draft.blocks = [DraftBlock(kind: .heading, text: "Sub"), DraftBlock(kind: .bulletList, text: "one\n\ntwo"),
                        DraftBlock(kind: .quote, text: "Q", attribution: "Someone"), DraftBlock(kind: .paragraph, text: "  ")]
        let article = DraftMarkup.previewArticle(draft) { _ in nil }
        XCTAssertNil(article.summary.publishedAt, "a preview never has a publication date")
        XCTAssertEqual(article.blocks.count, 3)
        guard case .list(_, let items) = article.blocks[1] else { return XCTFail() }
        XCTAssertEqual(items.count, 2)
    }

    func testFilter() {
        var a = Draft(now: Date()); a.headline = "Budget analysis"; a.editorialTypeWire = "analysis"
        var b = Draft(now: Date()); b.headline = "Market note"; b.serverLink = ServerLink(serverDraftID: "s", serverRevision: "1", remoteStatus: "draft", lastSyncedAt: .distantFuture, environment: "t")
        XCTAssertTrue(DraftFilter(query: "budget").matches(a))
        XCTAssertFalse(DraftFilter(query: "budget").matches(b))
        XCTAssertFalse(DraftFilter(link: .linked).matches(a))
        XCTAssertTrue(DraftFilter(link: .localOnly).matches(a))
        XCTAssertFalse(DraftFilter(link: .unsynced).matches(b))
        XCTAssertTrue(DraftFilter(editorialTypeWire: "analysis").matches(a))
    }
}

final class NewsroomGateAndClientTests: XCTestCase {
    let caps = NewsroomCapabilities(contractVersion: "1", supported: [.saveDraft, .submitForReview, .publish], allowed: [.saveDraft, .submitForReview, .unpublish])

    func testGateExplainsEveryMissingCondition() {
        XCTAssertEqual(NewsroomGate.availability(.publish, serviceConfigured: false, signedIn: true, centralAccessGranted: true, capabilities: caps).isAvailable, false)
        XCTAssertEqual(NewsroomGate.availability(.publish, serviceConfigured: true, signedIn: false, centralAccessGranted: true, capabilities: caps).reason,
                       "Sign in with HCG Connect to use newsroom actions.")
        XCTAssertEqual(NewsroomGate.availability(.publish, serviceConfigured: true, signedIn: true, centralAccessGranted: false, capabilities: caps).reason,
                       "HCG has not granted newsroom access to this account in this session.")
        XCTAssertEqual(NewsroomGate.availability(.publish, serviceConfigured: true, signedIn: true, centralAccessGranted: true, capabilities: caps).reason,
                       "The newsroom service hasn't authorised “Publish” for your account.")
        XCTAssertEqual(NewsroomGate.availability(.unpublish, serviceConfigured: true, signedIn: true, centralAccessGranted: true, capabilities: caps).reason,
                       "The newsroom service doesn't support “Unpublish” yet.", "allowed but unsupported is still unavailable")
        XCTAssertTrue(NewsroomGate.availability(.submitForReview, serviceConfigured: true, signedIn: true, centralAccessGranted: true, capabilities: caps).isAvailable)
    }

    static let base = "https://news.hakmicapitalgroup.com/api/test-newsroom/v1/"

    func client(_ transport: FakeTransport, token: String? = "t") -> NewsroomAPIClient {
        NewsroomAPIClient(baseURL: URL(string: Self.base)!, environment: "test", transport: transport, userAgent: "tests", token: { token })
    }

    func testConflictIsReportedAndNothingOverwritten() async {
        let current = #"{"current":{"id":"srv-1","headline":"Theirs","status":"draft","revision":"5"}}"#
        let transport = FakeTransport { _ in (409, Data(current.utf8)) }
        var draft = Draft(now: Date())
        draft.serverLink = ServerLink(serverDraftID: "srv-1", serverRevision: "4", remoteStatus: "draft", lastSyncedAt: Date(), environment: "test")
        do {
            _ = try await client(transport).saveDraft(draft, mediaRemoteIDs: [:])
            XCTFail("expected conflict")
        } catch NewsroomError.conflict(let server) {
            XCTAssertEqual(server.revision, "5")
        } catch { XCTFail("\(error)") }
        let request = transport.requests[0]
        XCTAssertEqual(request.httpMethod, "PUT")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("\"baseRevision\":\"4\""), "updates always carry the base revision")
    }

    func testDeniedAndSignedOutActions() async {
        let denied = FakeTransport { _ in (403, Data(#"{"message":"Publishing needs editor-in-chief approval in HCG."}"#.utf8)) }
        do {
            _ = try await client(denied).perform(.publish, serverID: "s", baseRevision: "1", scheduleAt: nil, note: nil)
            XCTFail()
        } catch { XCTAssertEqual(error as? NewsroomError, .denied("Publishing needs editor-in-chief approval in HCG.")) }

        let never = FakeTransport()
        do {
            _ = try await client(never, token: nil).queue()
            XCTFail()
        } catch { XCTAssertEqual(error as? NewsroomError, .notSignedIn) }
        XCTAssertTrue(never.requests.isEmpty)
    }

    func testOfflineFailsImmediatelyWithoutQueueing() async {
        let transport = FakeTransport { _ in throw TransportError.offline }
        do {
            _ = try await client(transport).saveDraft(Draft(now: Date()), mediaRemoteIDs: [:])
            XCTFail()
        } catch { XCTAssertEqual(error as? NewsroomError, .offline) }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testCapabilitiesIntersectAllowedWithSupported() async throws {
        let body = #"{"contractVersion":"1","supportedActions":["save_draft","submit"],"allowedActions":["submit","publish","made_up"],"authors":[{"id":"a1","name":"Fixture Author"}]}"#
        let caps = try await client(FakeTransport { _ in (200, Data(body.utf8)) }).capabilities()
        XCTAssertEqual(caps.allowed, [.submitForReview])
        XCTAssertEqual(caps.authors.map(\.name), ["Fixture Author"])
    }

    func testUnavailableServiceExplainsNotConfigured() async {
        do { _ = try await UnavailableNewsroomService().capabilities(); XCTFail() } catch {
            XCTAssertEqual(error as? NewsroomError, .notConfigured)
        }
    }
}
