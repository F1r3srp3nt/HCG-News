import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import HCGTestSupport
@testable import HCGConnect

// All endpoints, client IDs and tokens below are FICTIONAL test values on
// `*.test.invalid`-style or placeholder paths. They are not HCG configuration.

final class PKCETests: XCTestCase {
    func testRFC7636AppendixBVector() {
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testPortableSHA256KnownVectors() {
        func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
        XCTAssertEqual(hex(PortableSHA256.hash([])), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(hex(PortableSHA256.hash(Array("abc".utf8))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(hex(PortableSHA256.hash(Array(String(repeating: "a", count: 1000).utf8))),
                       "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    func testVerifierShapeAndUniqueness() {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let a = PKCE.makePair(), b = PKCE.makePair()
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertEqual(a.verifier.count, 64)
        XCTAssertTrue(a.verifier.allSatisfy(allowed.contains))
        XCTAssertEqual(PKCE.makePair(length: 10).verifier.count, 43, "clamped to RFC minimum")
        XCTAssertEqual(a.method, "S256")
    }
}

enum ConnectFixture {
    static let scheme = "com.hakmicapitalgroup.hcgnews"
    static var valid: [String: Any] {
        [
            "contractVersion": "1", "environment": "test", "approvedByFounder": true,
            "issuer": "https://id.hakmicapitalgroup.com/auth",
            "authorizationEndpoint": "https://id.hakmicapitalgroup.com/auth/oauth/authorize",
            "tokenEndpoint": "https://id.hakmicapitalgroup.com/auth/oauth/token",
            "signOutEndpoint": "https://id.hakmicapitalgroup.com/auth/oauth/revoke",
            "signOutFormat": "rfc7009",
            "appAccessEndpoint": "https://beta.hakmicapitalgroup.com/api/test/app-access",
            "clientID": "test-native-client",
            "redirectURI": "com.hakmicapitalgroup.hcgnews:/oauth/callback",
            "scopes": ["openid", "profile"],
            "appIdentifier": "hcg-news-test",
            "newsroomPermission": "test.newsroom.open",
            "newsroomURL": "https://beta.hakmicapitalgroup.com/test-newsroom",
        ]
    }

    static func state(_ connect: [String: Any]) -> ConnectConfigurationState {
        ConnectConfigurationLoader.load(JSONFixture.data(["connect": connect]), expectedRedirectScheme: scheme)
    }

    static var configuration: ConnectConfiguration { state(valid).configuration! }

    static func jwt(sub: String, name: String? = nil, role: String? = nil) -> String {
        var payload: [String: Any] = ["sub": sub]
        if let name { payload["name"] = name }
        if let role { payload["role"] = role }
        let data = JSONFixture.data(payload)
        let body = data.base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return "eyJhbGciOiJub25lIn0.\(body).sig"
    }
}

final class ConnectConfigurationTests: XCTestCase {
    func testAwaitingSetupWithoutFile() {
        XCTAssertEqual(ConnectConfigurationLoader.load(nil, expectedRedirectScheme: ConnectFixture.scheme), .awaitingSetup)
    }

    func testValidConfigurationIsReady() {
        let c = ConnectFixture.configuration
        XCTAssertEqual(c.callbackScheme, ConnectFixture.scheme)
        XCTAssertEqual(c.refreshEndpoint, c.tokenEndpoint, "refresh defaults to the token endpoint")
        XCTAssertTrue(c.ephemeralBrowserSession)
    }

    func testClientSecretIsRejected() {
        var c = ConnectFixture.valid
        c["clientSecret"] = "never"
        guard case .invalid(let problems) = ConnectFixture.state(c) else { return XCTFail() }
        XCTAssertTrue(problems[0].contains("client secret"))
    }

    func testServiceRoleKeyIsRejectedAnonKeyAccepted() {
        var c = ConnectFixture.valid
        c["providerPublicKey"] = ConnectFixture.jwt(sub: "x", role: "service_role")
        guard case .invalid = ConnectFixture.state(c) else { return XCTFail() }
        c["providerPublicKey"] = ConnectFixture.jwt(sub: "x", role: "anon")
        XCTAssertNotNil(ConnectFixture.state(c).configuration)
    }

    func testReusingAnotherAppsRedirectIsRejected() {
        var c = ConnectFixture.valid
        c["redirectURI"] = "hcgcardx://auth/callback"
        guard case .invalid(let problems) = ConnectFixture.state(c) else { return XCTFail() }
        XCTAssertTrue(problems.contains { $0.contains("callback scheme") })
    }

    func testAuthorizationMustComeFromHCGHosts() {
        var c = ConnectFixture.valid
        c["appAccessEndpoint"] = "https://evil.example/app-access"
        guard case .invalid = ConnectFixture.state(c) else { return XCTFail() }
        c = ConnectFixture.valid
        c["tokenEndpoint"] = "https://evil.example/token"
        guard case .invalid = ConnectFixture.state(c) else { return XCTFail() }
        c = ConnectFixture.valid
        c["authorizationEndpoint"] = "http://id.hakmicapitalgroup.com/auth/oauth/authorize"
        guard case .invalid = ConnectFixture.state(c) else { return XCTFail() }
    }

    func testProviderJSONRefreshNeedsPublicKeyAndUnapprovedIsInvalid() {
        var c = ConnectFixture.valid
        c["refreshFormat"] = "provider-json"
        guard case .invalid = ConnectFixture.state(c) else { return XCTFail() }
        c = ConnectFixture.valid
        c["approvedByFounder"] = false
        guard case .invalid = ConnectFixture.state(c) else { return XCTFail() }
    }
}

final class AuthorizationFlowTests: XCTestCase {
    let configuration = ConnectFixture.configuration

    func testAuthorizationURLCarriesPKCEAndState() {
        let attempt = AuthorizationAttempt(configuration: configuration, state: "s", nonce: "n",
                                           pkce: PKCEPair(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: attempt.url, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["client_id"], "test-native-client")
        XCTAssertEqual(items["redirect_uri"], "com.hakmicapitalgroup.hcgnews:/oauth/callback")
        XCTAssertEqual(items["scope"], "openid profile")
        XCTAssertEqual(items["state"], "s")
        XCTAssertEqual(items["code_challenge"], "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertNil(items["code_verifier"], "the verifier never travels to the browser")
    }

    func testCallbackValidation() throws {
        let attempt = AuthorizationAttempt(configuration: configuration, state: "expected")
        func callback(_ s: String) -> URL { URL(string: s)! }
        XCTAssertEqual(try AuthorizationCallback.code(from: callback("com.hakmicapitalgroup.hcgnews:/oauth/callback?code=abc&state=expected"),
                                                      attempt: attempt, configuration: configuration), "abc")
        XCTAssertThrowsError(try AuthorizationCallback.code(from: callback("com.hakmicapitalgroup.hcgnews:/oauth/callback?code=abc&state=other"),
                                                            attempt: attempt, configuration: configuration)) {
            XCTAssertEqual($0 as? CallbackError, .stateMismatch)
        }
        XCTAssertThrowsError(try AuthorizationCallback.code(from: callback("com.hakmicapitalgroup.hcgnews:/oauth/callback?code=abc"),
                                                            attempt: attempt, configuration: configuration)) {
            XCTAssertEqual($0 as? CallbackError, .stateMismatch)
        }
        XCTAssertThrowsError(try AuthorizationCallback.code(from: callback("com.hakmicapitalgroup.hcgnews:/elsewhere?code=abc&state=expected"),
                                                            attempt: attempt, configuration: configuration)) {
            XCTAssertEqual($0 as? CallbackError, .unexpectedRedirect)
        }
        XCTAssertThrowsError(try AuthorizationCallback.code(from: callback("com.hakmicapitalgroup.hcgnews:/oauth/callback?error=access_denied&error_description=No&state=expected"),
                                                            attempt: attempt, configuration: configuration)) {
            XCTAssertEqual($0 as? CallbackError, .accessDenied("No"))
        }
        XCTAssertThrowsError(try AuthorizationCallback.code(from: callback("com.hakmicapitalgroup.hcgnews:/oauth/callback?state=expected"),
                                                            attempt: attempt, configuration: configuration)) {
            XCTAssertEqual($0 as? CallbackError, .missingCode)
        }
    }

    func testAppAccessDecisionAllows() {
        let now = Date(timeIntervalSince1970: 1000)
        let granted = AppAccessDecision(appIdentifier: "a", subject: "s", status: .granted, permissions: ["p"], validUntil: now.addingTimeInterval(10))
        XCTAssertTrue(granted.allows("p", at: now))
        XCTAssertFalse(granted.allows("other", at: now))
        XCTAssertFalse(granted.allows("p", at: now.addingTimeInterval(11)), "expired decisions are not honoured")
        let denied = AppAccessDecision(appIdentifier: "a", subject: "s", status: .denied, permissions: ["p"])
        XCTAssertFalse(denied.allows("p", at: now))
    }
}

// MARK: - Coordinator

final class MemorySessionStore: ConnectSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: ConnectSession?
    private(set) var deleteCount = 0

    init(_ session: ConnectSession? = nil) { self.session = session }

    var current: ConnectSession? { lock.withLock { session } }
    func load() throws -> ConnectSession? { lock.withLock { session } }
    func save(_ session: ConnectSession) throws { lock.withLock { self.session = session } }
    func delete() throws { lock.withLock { session = nil; deleteCount += 1 } }
}

struct ScriptedBrowser: BrowserAuthenticating {
    enum Outcome: Sendable { case returnCode(String), cancel, deny, wrongState }
    let outcome: Outcome

    func authenticate(url: URL, callbackScheme: String, ephemeral: Bool) async throws -> URL {
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        switch outcome {
        case .returnCode(let code):
            return URL(string: "\(callbackScheme):/oauth/callback?code=\(code)&state=\(state)")!
        case .cancel:
            throw BrowserAuthenticationError.cancelled
        case .deny:
            return URL(string: "\(callbackScheme):/oauth/callback?error=access_denied&state=\(state)")!
        case .wrongState:
            return URL(string: "\(callbackScheme):/oauth/callback?code=x&state=forged")!
        }
    }
}

final class CoordinatorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let subject = "11111111-2222-3333-4444-555555555555"

    func tokenBody(expiresIn: Double = 3600, refresh: String = "refresh-1", sub: String? = nil) -> Data {
        JSONFixture.data(["access_token": ConnectFixture.jwt(sub: sub ?? subject, name: "Test Reader"),
                          "refresh_token": refresh, "expires_in": expiresIn, "token_type": "bearer"])
    }

    func decision(_ status: String, permissions: [String] = [], app: String = "hcg-news-test", sub: String? = nil) -> Data {
        JSONFixture.data(["appIdentifier": app, "subject": sub ?? subject, "status": status, "permissions": permissions])
    }

    func coordinator(_ state: ConnectConfigurationState = .ready(ConnectFixture.configuration),
                     browser: ScriptedBrowser.Outcome = .returnCode("code-1"),
                     store: MemorySessionStore = MemorySessionStore(),
                     transport: FakeTransport) -> HCGConnectCoordinator {
        let fixedNow = now
        return HCGConnectCoordinator(configuration: state, browser: ScriptedBrowser(outcome: browser), store: store,
                                     transport: transport, userAgent: "HCGNews-Tests", now: { fixedNow })
    }

    func testUnconfiguredMakesNoRequestsAndClaimsNothing() async {
        let transport = FakeTransport()
        let c = coordinator(.awaitingSetup, transport: transport)
        await c.restore()
        await c.signIn()
        await c.checkAppAccess()
        let token = await c.validAccessToken()
        let status = await c.status()
        XCTAssertNil(token)
        XCTAssertEqual(status.authentication, .unavailable)
        XCTAssertNil(status.newsroomURL)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSignInStoresSessionChecksAccessAndDoesNotGrantNewsroomWithoutPermission() async throws {
        let store = MemorySessionStore()
        let tokens = tokenBody()
        let granted = decision("granted", permissions: ["test.read"])
        let transport = FakeTransport { request in
            if request.url!.path.hasSuffix("/token") { return (200, tokens) }
            if request.url!.path.hasSuffix("/app-access") { return (200, granted) }
            return (404, Data())
        }
        let c = coordinator(store: store, transport: transport)
        await c.signIn()
        let status = await c.status()
        XCTAssertEqual(status.authentication, .signedIn(subject: subject, displayName: "Test Reader"))
        guard case .decided(let d) = status.access else { return XCTFail("\(status.access)") }
        XCTAssertEqual(d.status, .granted)
        XCTAssertNil(status.newsroomURL, "signing in never grants the newsroom by itself")
        XCTAssertNotNil(store.current)

        // Token exchange carried PKCE verifier and no secret.
        let exchange = transport.requests.first { $0.url!.path.hasSuffix("/token") }!
        let body = String(data: exchange.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code_verifier="))
        XCTAssertTrue(body.contains("client_id=test-native-client"))
        XCTAssertFalse(body.contains("secret"))
        // App Access request names this app and carries the bearer token in a header only.
        let access = transport.requests.first { $0.url!.path.hasSuffix("/app-access") }!
        XCTAssertTrue(access.url!.query!.contains("app=hcg-news-test"))
        XCTAssertFalse(access.url!.absoluteString.contains("refresh-1"))
        XCTAssertNotNil(access.value(forHTTPHeaderField: "Authorization"))
    }

    func testNewsroomEntryRequiresCentralPermission() async {
        let tokens = tokenBody()
        let granted = decision("granted", permissions: ["test.newsroom.open"])
        let transport = FakeTransport { request in
            request.url!.path.hasSuffix("/token") ? (200, tokens) : (200, granted)
        }
        let c = coordinator(transport: transport)
        await c.signIn()
        let status = await c.status()
        XCTAssertEqual(status.newsroomURL?.absoluteString, "https://beta.hakmicapitalgroup.com/test-newsroom")
    }

    func testDecisionForAnotherAppOrAccountIsRejected() async {
        let tokens = tokenBody()
        let foreign = decision("granted", permissions: ["test.newsroom.open"], app: "hcg-cardx")
        let transport = FakeTransport { request in
            request.url!.path.hasSuffix("/token") ? (200, tokens) : (200, foreign)
        }
        let c = coordinator(transport: transport)
        await c.signIn()
        let status = await c.status()
        guard case .failed = status.access else { return XCTFail("\(status.access)") }
        XCTAssertNil(status.newsroomURL)
    }

    func testCancellationLeavesUserSignedOutWithoutNetworkCalls() async {
        let transport = FakeTransport()
        let c = coordinator(browser: .cancel, transport: transport)
        await c.signIn()
        let status = await c.status()
        XCTAssertEqual(status.authentication, .signedOut)
        XCTAssertEqual(status.lastEvent, .cancelled)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testDeniedAndForgedStateAreHandled() async {
        let transport = FakeTransport()
        let denied = coordinator(browser: .deny, transport: transport)
        await denied.signIn()
        let deniedStatus = await denied.status()
        XCTAssertEqual(deniedStatus.lastEvent, .denied(nil))

        let forged = coordinator(browser: .wrongState, transport: transport)
        await forged.signIn()
        let forgedStatus = await forged.status()
        XCTAssertEqual(forgedStatus.authentication, .signedOut)
        guard case .failed? = forgedStatus.lastEvent else { return XCTFail() }
        XCTAssertTrue(transport.requests.isEmpty, "a forged callback never reaches the token endpoint")
    }

    func testExpiredTokenRefreshesOnceAcrossConcurrentCallers() async {
        let stale = ConnectSession(accessToken: "old", refreshToken: "refresh-0", expiresAt: now.addingTimeInterval(-10),
                                   subject: subject, displayName: nil, environment: "test")
        let store = MemorySessionStore(stale)
        let tokens = tokenBody(refresh: "refresh-rotated")
        let transport = FakeTransport { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return (200, tokens)
        }
        let c = coordinator(store: store, transport: transport)
        await c.restore()
        async let a = c.validAccessToken()
        async let b = c.validAccessToken()
        async let d = c.validAccessToken()
        let results = await [a, b, d]
        XCTAssertTrue(results.allSatisfy { $0 != nil && $0 != "old" })
        XCTAssertEqual(transport.requests.count, 1, "refresh is single-flight")
        XCTAssertEqual(store.current?.refreshToken, "refresh-rotated")
    }

    func testRejectedRefreshExpiresSessionAndClearsKeychain() async {
        let stale = ConnectSession(accessToken: "old", refreshToken: "revoked", expiresAt: now.addingTimeInterval(-10),
                                   subject: subject, displayName: nil, environment: "test")
        let store = MemorySessionStore(stale)
        let transport = FakeTransport { _ in (400, JSONFixture.data(["error": "invalid_grant"])) }
        let c = coordinator(store: store, transport: transport)
        await c.restore()
        let token = await c.validAccessToken()
        let status = await c.status()
        XCTAssertNil(token)
        XCTAssertEqual(status.authentication, .expired)
        XCTAssertNil(store.current)
    }

    func testOfflineRefreshKeepsSessionForLaterRetry() async {
        let stale = ConnectSession(accessToken: "old", refreshToken: "r", expiresAt: now.addingTimeInterval(-10),
                                   subject: subject, displayName: nil, environment: "test")
        let store = MemorySessionStore(stale)
        let c = coordinator(store: store, transport: FakeTransport { _ in throw TransportError.offline })
        await c.restore()
        let token = await c.validAccessToken()
        XCTAssertNil(token, "an expired token is not used")
        XCTAssertNotNil(store.current, "the session is kept for a retry when back online")
    }

    func testAppAccess401RefreshesThenRetries() async {
        let valid = ConnectSession(accessToken: "a1", refreshToken: "r1", expiresAt: now.addingTimeInterval(3600),
                                   subject: subject, displayName: nil, environment: "test")
        let tokens = tokenBody()
        let granted = decision("granted")
        let transport = FakeTransport { request in
            if request.url!.path.hasSuffix("/token") { return (200, tokens) }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer a1" ? (401, Data()) : (200, granted)
        }
        let c = coordinator(store: MemorySessionStore(valid), transport: transport)
        await c.restore()
        await c.checkAppAccess()
        let status = await c.status()
        guard case .decided(let d) = status.access else { return XCTFail("\(status.access)") }
        XCTAssertEqual(d.status, .granted)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testCentralRevocationClearsLocalSession() async {
        let valid = ConnectSession(accessToken: "a1", refreshToken: "r1", expiresAt: now.addingTimeInterval(3600),
                                   subject: subject, displayName: nil, environment: "test")
        let store = MemorySessionStore(valid)
        let revoked = decision("revoked")
        let c = coordinator(store: store, transport: FakeTransport { _ in (200, revoked) })
        await c.restore()
        await c.checkAppAccess()
        let status = await c.status()
        XCTAssertEqual(status.authentication, .signedOut)
        XCTAssertEqual(status.lastEvent, .revoked)
        XCTAssertNil(store.current)
    }

    func testDeniedAccessIsReportedNotGranted() async {
        let valid = ConnectSession(accessToken: "a1", refreshToken: "r1", expiresAt: now.addingTimeInterval(3600),
                                   subject: subject, displayName: nil, environment: "test")
        let c = coordinator(store: MemorySessionStore(valid), transport: FakeTransport { _ in (403, Data()) })
        await c.restore()
        await c.checkAppAccess()
        let status = await c.status()
        XCTAssertEqual(status.access, .refused(reason: nil))
        XCTAssertNil(status.newsroomURL)
    }

    func testSignOutReportsCentralOutcomeHonestly() async {
        let session = ConnectSession(accessToken: "a1", refreshToken: "r1", expiresAt: now.addingTimeInterval(3600),
                                     subject: subject, displayName: nil, environment: "test")
        // Endpoint acknowledges.
        let store1 = MemorySessionStore(session)
        let ack = coordinator(store: store1, transport: FakeTransport { _ in (200, Data()) })
        await ack.restore()
        let report1 = await ack.signOut()
        XCTAssertEqual(report1, SignOutReport(localSessionCleared: true, central: .acknowledged))
        XCTAssertNil(store1.current)

        // Endpoint unreachable: local session still cleared, failure reported.
        let store2 = MemorySessionStore(session)
        let offline = coordinator(store: store2, transport: FakeTransport { _ in throw TransportError.offline })
        await offline.restore()
        let report2 = await offline.signOut()
        XCTAssertTrue(report2.localSessionCleared)
        guard case .failed = report2.central else { return XCTFail() }
        XCTAssertNil(store2.current)

        // No endpoint configured: only local.
        var noEndpoint = ConnectFixture.valid
        noEndpoint.removeValue(forKey: "signOutEndpoint")
        noEndpoint.removeValue(forKey: "signOutFormat")
        let store3 = MemorySessionStore(session)
        let transport3 = FakeTransport()
        let local = coordinator(ConnectFixture.state(noEndpoint), store: store3, transport: transport3)
        await local.restore()
        let report3 = await local.signOut()
        XCTAssertEqual(report3.central, .notConfigured)
        XCTAssertTrue(transport3.requests.isEmpty)
    }

    func testSessionFromAnotherEnvironmentIsDiscarded() async {
        let other = ConnectSession(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(3600),
                                   subject: subject, displayName: nil, environment: "production")
        let store = MemorySessionStore(other)
        let c = coordinator(store: store, transport: FakeTransport())
        await c.restore()
        let status = await c.status()
        XCTAssertEqual(status.authentication, .signedOut)
        XCTAssertNil(store.current)
    }
}
