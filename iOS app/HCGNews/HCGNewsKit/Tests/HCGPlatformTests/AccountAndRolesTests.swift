import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import HCGConnect
import HCGTestSupport
@testable import HCGPlatform

final class HCGAccountSessionTests: XCTestCase {
    func make(_ transport: FakeTransport, store: MemorySessionStore = MemorySessionStore(), now: Date = fixedNow) -> HCGAccountSession {
        HCGAccountSession(client: PlatformClient(configuration: testPlatform, transport: transport, userAgent: "test"),
                          store: store, now: { now })
    }

    func testSignInUsesThePasswordGrantAndStoresOnlyTokens() async throws {
        let transport = FakeTransport { _ in (200, tokenResponse()) }
        let store = MemorySessionStore()
        let account = make(transport, store: store)
        let user = try await account.signIn(email: " staff@example.test ", password: "pw-123")
        XCTAssertEqual(user.id, "user-1")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.path, "/auth/v1/token")
        XCTAssertEqual(request.query["grant_type"], "password")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), testAnonKey)
        XCTAssertEqual(request.bodyObject["email"] as? String, "staff@example.test")
        let stored = try XCTUnwrap(store.current)
        XCTAssertEqual(stored.accessToken, "access-1")
        XCTAssertEqual(stored.subject, "user-1")
        let encoded = String(decoding: try HCGJSON.makeEncoder().encode(stored), as: UTF8.self)
        XCTAssertFalse(encoded.contains("pw-123"), "the password is never stored")
        let state = await account.state
        XCTAssertEqual(state, .signedIn(user))
    }

    func testWrongPasswordAndUnconfirmedEmailAreReportedPlainly() async {
        let transport = FakeTransport { _ in (400, json(["error": "invalid_grant", "error_description": "Invalid login credentials"])) }
        do { _ = try await make(transport).signIn(email: "a@b.c", password: "x"); XCTFail() }
        catch let e as HCGSignInError { XCTAssertEqual(e, .invalidCredentials) } catch { XCTFail("\(error)") }
        transport.setHandler { _ in (400, json(["error_code": "email_not_confirmed", "msg": "Email not confirmed"])) }
        do { _ = try await make(transport).signIn(email: "a@b.c", password: "x"); XCTFail() }
        catch let e as HCGSignInError { XCTAssertEqual(e, .emailNotConfirmed) } catch { XCTFail("\(error)") }
    }

    func testTokenNearExpiryIsRefreshedOnceForConcurrentCallers() async throws {
        let store = MemorySessionStore(ConnectSession(accessToken: "old", refreshToken: "r-old", expiresAt: fixedNow.addingTimeInterval(30),
                                                      subject: "user-1", displayName: "staff@example.test",
                                                      environment: "hcg-platform:qggdyzoydveafkmjgkpq"))
        let transport = FakeTransport { _ in (200, tokenResponse(access: "new", refresh: "r-new")) }
        let account = make(transport, store: store)
        await account.restore()
        async let a = account.validAccessToken()
        async let b = account.validAccessToken()
        let tokens = await [a, b]
        XCTAssertEqual(tokens, ["new", "new"])
        XCTAssertEqual(transport.requests.filter { $0.query["grant_type"] == "refresh_token" }.count, 1)
        XCTAssertEqual(store.current?.refreshToken, "r-new", "rotated refresh token is stored")
    }

    func testRevokedRefreshTokenExpiresTheSessionAndClearsTheKeychain() async {
        let store = MemorySessionStore(ConnectSession(accessToken: "old", refreshToken: "r", expiresAt: fixedNow.addingTimeInterval(10),
                                                      subject: "user-1", displayName: nil, environment: "hcg-platform:qggdyzoydveafkmjgkpq"))
        let transport = FakeTransport { _ in (400, json(["error_code": "refresh_token_not_found"])) }
        let account = make(transport, store: store)
        await account.restore()
        let token = await account.validAccessToken()
        XCTAssertNil(token)
        XCTAssertNil(store.current)
        guard case .expired = await account.state else { return XCTFail("expected expired") }
    }

    func testOfflineRefreshKeepsAStillValidSession() async {
        let store = MemorySessionStore(ConnectSession(accessToken: "old", refreshToken: "r", expiresAt: fixedNow.addingTimeInterval(60),
                                                      subject: "user-1", displayName: nil, environment: "hcg-platform:qggdyzoydveafkmjgkpq"))
        let account = make(FakeTransport { _ in throw TransportError.offline }, store: store)
        await account.restore()
        let token = await account.validAccessToken()
        XCTAssertEqual(token, "old")
        XCTAssertNotNil(store.current)
    }

    func testSessionsFromAnotherSetupAreNotRestored() async {
        let store = MemorySessionStore(ConnectSession(accessToken: "a", refreshToken: "r", expiresAt: fixedNow.addingTimeInterval(999),
                                                      subject: "u", displayName: nil, environment: "oauth-env"))
        let account = make(FakeTransport(), store: store)
        await account.restore()
        let state = await account.state
        XCTAssertEqual(state, .signedOut)
        XCTAssertNil(store.current)
    }

    func testSignOutRevokesThisDeviceSessionAndAlwaysClearsLocally() async throws {
        let transport = FakeTransport { request in request.path.hasSuffix("/logout") ? (204, Data()) : (200, tokenResponse()) }
        let store = MemorySessionStore()
        let account = make(transport, store: store)
        _ = try await account.signIn(email: "a@b.c", password: "p")
        let outcome = await account.signOut()
        XCTAssertTrue(outcome.revokedOnServer)
        let logout = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(logout.query["scope"], "local")
        XCTAssertEqual(logout.bearer, "access-1")
        XCTAssertNil(store.current)

        _ = try await account.signIn(email: "a@b.c", password: "p")
        transport.setHandler { _ in throw TransportError.offline }
        let offline = await account.signOut()
        XCTAssertFalse(offline.revokedOnServer)
        XCTAssertTrue(offline.message.contains("at most an hour"))
        XCTAssertNil(store.current)
    }

    func testRejectedTokenIsRefreshedAndRetriedOnceThenGivesUp() async throws {
        let calls = Counter()
        let transport = FakeTransport { request in
            if request.path == "/auth/v1/token" { return (200, tokenResponse(access: request.query["grant_type"] == "password" ? "a1" : "a2")) }
            return (401, json(["code": "PGRST301", "message": "JWT expired"]))
        }
        let account = make(transport)
        _ = try await account.signIn(email: "a@b.c", password: "p")
        let caller = AuthorizedCaller(account: account)
        do {
            _ = try await caller.call { token -> Int in
                calls.increment()
                return try await PlatformClient(configuration: testPlatform, transport: transport, userAgent: "t")
                    .send(URLRequest(url: URL(string: "https://qggdyzoydveafkmjgkpq.supabase.co/rest/v1/x")!)).1.statusCode
            }
            XCTFail("should fail")
        } catch let e as PlatformError { XCTAssertEqual(e, .unauthorized) }
        XCTAssertEqual(calls.value, 2, "one retry after refresh, no loop")
    }
}

final class NewsroomRoleTests: XCTestCase {
    func signedInAccount(_ transport: FakeTransport) async throws -> HCGAccountSession {
        let account = HCGAccountSession(client: PlatformClient(configuration: testPlatform, transport: transport, userAgent: "t"),
                                        store: MemorySessionStore(), now: { fixedNow })
        _ = try await account.signIn(email: "a@b.c", password: "p")
        return account
    }

    func testRolesComeFromTheServerFunctionWithThePersonsToken() async throws {
        let transport = FakeTransport { request in
            if request.path == "/auth/v1/token" { return (200, tokenResponse()) }
            let key = request.bodyObject["_feature_key"] as? String
            return (200, Data((key == "news.editor" ? "true" : "false").utf8))
        }
        let account = try await signedInAccount(transport)
        let resolver = NewsroomRoleResolver(client: PlatformClient(configuration: testPlatform, transport: transport, userAgent: "t"),
                                            caller: AuthorizedCaller(account: account))
        let permissions = try await resolver.permissions(userID: "user-1")
        XCTAssertEqual(permissions.roles, [.editor])
        let rpc = transport.requests.filter { $0.path == "/rest/v1/rpc/news_has_feature" }
        XCTAssertEqual(rpc.count, 5)
        XCTAssertTrue(rpc.allSatisfy { $0.bearer == "access-1" && $0.httpMethod == "POST" && $0.bodyObject["_user_id"] as? String == "user-1" })
        XCTAssertEqual(Set(rpc.compactMap { $0.bodyObject["_feature_key"] as? String }),
                       ["news.administrator", "news.editor_in_chief", "news.editor", "news.journalist", "news.contributor"])
    }

    func testAnyFailedRoleCheckFailsTheWholeCheck() async throws {
        let transport = FakeTransport { request in
            if request.path == "/auth/v1/token" { return (200, tokenResponse()) }
            if request.bodyObject["_feature_key"] as? String == "news.contributor" { return (503, Data()) }
            return (200, Data("true".utf8))
        }
        let account = try await signedInAccount(transport)
        let resolver = NewsroomRoleResolver(client: PlatformClient(configuration: testPlatform, transport: transport, userAgent: "t"),
                                            caller: AuthorizedCaller(account: account))
        do { _ = try await resolver.permissions(userID: "user-1"); XCTFail("partial answer accepted") }
        catch let e as PlatformError { XCTAssertEqual(e, .unavailable) }
    }

    func testPermissionRulesMatchTheWebsite() {
        let contributor = NewsroomPermissions(roles: [.contributor], checkedAt: fixedNow)
        XCTAssertTrue(contributor.canEdit(createdBy: "me", status: "draft", userID: "me"))
        XCTAssertTrue(contributor.canEdit(createdBy: "me", status: "in_review", userID: "me"))
        XCTAssertFalse(contributor.canEdit(createdBy: "me", status: "approved", userID: "me"))
        XCTAssertFalse(contributor.canEdit(createdBy: "other", status: "draft", userID: "me"))
        XCTAssertEqual(contributor.allowedStatuses, [.draft, .inReview])
        XCTAssertFalse(contributor.canPublish)

        let editor = NewsroomPermissions(roles: [.editor], checkedAt: fixedNow)
        XCTAssertTrue(editor.canEdit(createdBy: "other", status: "published", userID: "me"))
        XCTAssertEqual(editor.allowedStatuses, [.draft, .inReview, .approved])
        XCTAssertFalse(editor.canPublish(fromStatus: "approved"))

        let chief = NewsroomPermissions(roles: [.editorInChief], checkedAt: fixedNow)
        XCTAssertTrue(chief.canPublish(fromStatus: "approved"))
        XCTAssertFalse(chief.canPublish(fromStatus: "in_review"), "approval is required before publication")
        XCTAssertFalse(chief.canViewAudit)

        let admin = NewsroomPermissions(roles: [.administrator], checkedAt: fixedNow)
        XCTAssertTrue(admin.canViewAudit)
        XCTAssertEqual(admin.allowedStatuses.count, 5)
        XCTAssertFalse(NewsroomPermissions.none.isStaff)
        XCTAssertFalse(NewsroomPermissions.none.canEdit(createdBy: "me", status: "draft", userID: "me"))
    }
}
