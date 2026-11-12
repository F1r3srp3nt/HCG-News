import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import HCGTestSupport
import NewsCore
import HCGConnect
import HCGPlatform
@testable import NewsAppModel

// Fictional rows and accounts only. No live HCG service is contacted.

private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFnZ2R5em95ZHZlYWZrbWpna3BxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1ODQwODQsImV4cCI6MjA5ODE2MDA4NH0.OLbNhV_hvWwS_BqgYVxwU9TZ9P05lX2Fp-ake-hAJ4M"

nonisolated(unsafe) let platformConfigurationJSON: [String: Any] = ["hcgPlatform": [
    "environment": "production", "projectURL": "https://qggdyzoydveafkmjgkpq.supabase.co", "publicClientKey": anonKey,
    "websiteURL": "https://beta.hakmicapitalgroup.com", "publicationURL": "https://news.hakmicapitalgroup.com",
    "approvedByFounder": true,
]]

private func body(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }

/// A scripted HCG: one staff account ("user-1") with the given roles.
final class FakeHCG: @unchecked Sendable {
    let lock = NSLock()
    var roles: Set<String>
    var revision = "2026-11-10T09:00:00+00:00"
    var title = "Test draft — not for publication"
    var status = "draft"
    var patchFails: Int? = nil
    var userEndpointStatus = 200
    init(roles: Set<String>) { self.roles = roles }

    func row() -> [String: Any] {
        ["id": "55555555-5555-5555-5555-555555555555", "title": title, "subtitle": NSNull(), "slug": "test-draft",
         "excerpt": NSNull(), "body": "<p>Fictional body.</p>", "status": status, "content_type": "news",
         "published_at": NSNull(), "created_at": "2026-11-09T09:00:00+00:00", "updated_at": revision, "created_by": "user-1",
         "author_id": NSNull(), "category_id": "c1", "featured_image_url": NSNull(), "featured_image_alt": NSNull(),
         "featured_image_caption": NSNull(), "featured_image_credit": NSNull(), "is_featured": false, "is_breaking": false,
         "is_demo": false, "seo_title": NSNull(), "seo_description": NSNull(), "tags": [], "sources": NSNull(),
         "correction_notes": NSNull(), "view_count": 0]
    }

    func handle(_ r: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        let path = r.url?.path ?? ""
        switch path {
        case "/auth/v1/token":
            return (200, body(["access_token": "tok", "refresh_token": "ref", "expires_in": 3600,
                               "user": ["id": "user-1", "email": "staff@example.test"]]))
        case "/auth/v1/user": return (userEndpointStatus, body(["id": "user-1", "email": "staff@example.test"]))
        case "/auth/v1/logout": return (204, Data())
        case "/rest/v1/rpc/news_has_feature":
            let key = ((try? JSONSerialization.jsonObject(with: r.httpBody ?? Data())) as? [String: Any])?["_feature_key"] as? String ?? ""
            return (200, Data((roles.contains(key) ? "true" : "false").utf8))
        case "/api/public/mobile/workspaces":
            return (200, body(["roles": [], "workspaces": [["id": "erp", "permitted": roles.contains("news.administrator"), "available": true]]]))
        case "/rest/v1/news_categories": return (200, body([["id": "c1", "name": "Markets", "slug": "markets", "is_visible": true]]))
        case "/rest/v1/news_authors": return (200, body([]))
        case "/rest/v1/news_article_versions": return (201, Data())
        case "/rest/v1/news_articles":
            if r.httpMethod == "PATCH" {
                if let s = patchFails { return (s, body(["message": "fail"])) }
                let expected = r.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "updated_at" }?.value }
                guard expected == "eq.\(revision)" else { return (200, body([])) }
                let changes = (try? JSONSerialization.jsonObject(with: r.httpBody ?? Data())) as? [String: Any] ?? [:]
                if let t = changes["title"] as? String { title = t }
                if let s = changes["status"] as? String { status = s }
                revision = "2026-11-10T1\(Int.random(in: 0...9)):00:00+00:00"
                return (200, body([row()]))
            }
            return (200, body([row()]))
        default: return (404, Data())
        }
    }
}

@MainActor
final class PlatformModelTests: XCTestCase {
    nonisolated(unsafe) var root: URL!
    nonisolated override func setUp() { root = tempRoot() }
    nonisolated override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func container(_ hcg: FakeHCG, store: MemorySessionStore = MemorySessionStore()) async -> AppContainer {
        let transport = FakeTransport { hcg.handle($0) }
        let platform = PlatformServices(transport: transport, browser: NeverBrowser(), sessionStore: MemorySessionStore(),
                                        userAgent: "tests", redirectScheme: scheme, appVersion: "test", accountStore: store)
        let stores = LocalStores.rooted(at: root, bundledConfiguration: JSONFixture.data(platformConfigurationJSON), redirectScheme: scheme)
        return await AppContainer(platform: platform, stores: stores)
    }

    func testBundledPlatformConfigurationConnectsTheRealServices() async {
        let c = await container(FakeHCG(roles: []))
        XCTAssertTrue(c.environment.service is PublicationContentService)
        XCTAssertNotNil(c.environment.platformAccount)
        XCTAssertNotNil(c.environment.newsroomDesk)
        XCTAssertFalse(c.environment.showsNewsroomEntry, "no newsroom entry before HCG grants a role")
    }

    func testReaderWithoutNewsroomRoleNeverSeesTheNewsroom() async {
        let c = await container(FakeHCG(roles: []))
        let account = c.environment.platformAccount!
        await account.signIn(email: "reader@example.test", password: "p")
        XCTAssertTrue(account.isSignedIn)
        XCTAssertEqual(account.permissions, .ready(account.currentPermissions))
        XCTAssertFalse(account.currentPermissions.isStaff)
        XCTAssertFalse(c.environment.showsNewsroomEntry)
        let desk = c.environment.newsroomDesk!
        await desk.load()
        XCTAssertEqual(desk.phase, .failed("Your account has no HCG News newsroom role."))
        XCTAssertTrue(desk.articles.isEmpty)
    }

    func testStaffGetTheNewsroomAndSignOutClearsAccountData() async {
        let store = MemorySessionStore()
        let c = await container(FakeHCG(roles: ["news.journalist"]), store: store)
        let account = c.environment.platformAccount!
        await account.signIn(email: "staff@example.test", password: "p")
        XCTAssertEqual(account.currentPermissions.roles, [.journalist])
        XCTAssertTrue(c.environment.showsNewsroomEntry)
        XCTAssertEqual(account.workspaces.value?.workspace("erp")?.permitted, false)
        let desk = c.environment.newsroomDesk!
        await desk.load()
        XCTAssertEqual(desk.articles.count, 1)

        await account.signOut()
        XCTAssertNil(store.current)
        XCTAssertFalse(c.environment.showsNewsroomEntry)
        XCTAssertTrue(desk.articles.isEmpty, "account caches are cleared on sign-out")
        XCTAssertEqual(account.permissions, .notChecked)
        XCTAssertTrue(account.lastMessage?.contains("Signed out") ?? false)
    }

    func testRevokedSessionIsDetectedWhenAccessIsRechecked() async {
        let hcg = FakeHCG(roles: ["news.editor"])
        let c = await container(hcg)
        let account = c.environment.platformAccount!
        await account.signIn(email: "staff@example.test", password: "p")
        XCTAssertTrue(c.environment.showsNewsroomEntry)
        hcg.lock.withLock { hcg.userEndpointStatus = 403 }
        // Refresh also fails once the session is revoked.
        await account.refreshAccess()
        XCTAssertFalse(account.isSignedIn)
        XCTAssertNotNil(account.expiredReason)
        XCTAssertFalse(c.environment.showsNewsroomEntry)
    }

    func editor(_ hcg: FakeHCG) async -> (AppContainer, RemoteArticleEditorModel) {
        let c = await container(hcg)
        await c.environment.platformAccount!.signIn(email: "staff@example.test", password: "p")
        let desk = c.environment.newsroomDesk!
        await desk.load()
        let editor = await desk.openEditor(id: "55555555-5555-5555-5555-555555555555")!
        return (c, editor)
    }

    func testConflictKeepsLocalEditsAndNeverOverwritesSilently() async throws {
        let hcg = FakeHCG(roles: ["news.editor"])
        let (_, editor) = await editor(hcg)
        editor.fields.title = "My edit"
        hcg.lock.withLock { hcg.revision = "2026-11-10T22:22:22+00:00"; hcg.title = "Their edit" }
        await editor.save()
        guard case .conflict(let server) = editor.phase else { return XCTFail("\(editor.phase)") }
        XCTAssertEqual(server.fields.title, "Their edit")
        XCTAssertEqual(editor.fields.title, "My edit", "local edits survive a conflict")
        let backup = await editor.desk.backups.load(user: "user-1", article: editor.id)
        XCTAssertEqual(backup?.fields.title, "My edit", "and are stored on the device")

        editor.keepMineOverServer()
        await editor.save()
        guard case .saved = editor.phase else { return XCTFail("\(editor.phase)") }
        XCTAssertEqual(hcg.lock.withLock { hcg.title }, "My edit")
        let after = await editor.desk.backups.load(user: "user-1", article: editor.id)
        XCTAssertNil(after, "backup removed once saved")
    }

    func testUnsavedEditsSurviveAFailedSaveAndAreOfferedAgain() async throws {
        let hcg = FakeHCG(roles: ["news.editor"])
        let (c, editor) = await editor(hcg)
        editor.fields.title = "Unsaved work"
        hcg.lock.withLock { hcg.patchFails = 503 }
        await editor.save()
        guard case .failed(let message) = editor.phase else { return XCTFail() }
        XCTAssertTrue(message.contains("kept on this device"))

        // Later (e.g. after a relaunch) the same article offers the stored edits.
        let reopened = await c.environment.newsroomDesk!.openEditor(id: editor.id)!
        await reopened.checkForBackup()
        XCTAssertEqual(reopened.recoverableBackup?.fields.title, "Unsaved work")
        reopened.recoverBackup()
        XCTAssertEqual(reopened.fields.title, "Unsaved work")
        XCTAssertTrue(reopened.hasUnsavedChanges)
    }

    func testStatusChangesFollowTheRoleAndPublicationNeedsApproval() async {
        let journalist = FakeHCG(roles: ["news.journalist"])
        let (_, j) = await editor(journalist)
        XCTAssertEqual(j.availableTransitions, [.inReview])
        await j.change(to: .published)
        guard case .failed = j.phase else { return XCTFail("journalist published") }
        XCTAssertEqual(journalist.lock.withLock { journalist.status }, "draft")
        await j.change(to: .inReview)
        XCTAssertEqual(journalist.lock.withLock { journalist.status }, "in_review")

        let chief = FakeHCG(roles: ["news.editor_in_chief"])
        let (_, e) = await editor(chief)
        XCTAssertTrue(e.publicationProblems.contains("Approval is required before publication."))
        await e.change(to: .approved)
        XCTAssertEqual(chief.lock.withLock { chief.status }, "approved")
        await e.change(to: .published, scheduleAt: Date().addingTimeInterval(-60))
        guard case .failed(let m) = e.phase else { return XCTFail() }
        XCTAssertEqual(m, "Choose a future publication date.")
        await e.change(to: .published, scheduleAt: Date().addingTimeInterval(3600))
        XCTAssertEqual(chief.lock.withLock { chief.status }, "published")
    }

    func testUntouchedBodyIsNeverResent() async {
        let hcg = FakeHCG(roles: ["news.editor"])
        let (_, editor) = await editor(hcg)
        XCTAssertEqual(editor.bodyMode, .editable)
        editor.blocks = editor.blocks   // no real change
        XCTAssertFalse(editor.hasUnsavedChanges)
        editor.blocks[0].text = "Changed"
        XCTAssertTrue(editor.hasUnsavedChanges)
        XCTAssertEqual(editor.fields.body, "<p>Changed</p>")
    }

    func testPlatformConfigurationImportPreviewNamesTheDestinations() async {
        let c = await container(FakeHCG(roles: []))
        let preview = await c.preview(JSONFixture.data(platformConfigurationJSON), as: .publication)
        XCTAssertTrue(preview.problems.isEmpty, "\(preview.problems)")
        XCTAssertTrue(preview.destinations.contains { $0.contains("qggdyzoydveafkmjgkpq.supabase.co") })
    }
}
