import Foundation
import HCGTransport
import HCGConnect

/// The signed-in HCG account, as the identity service reported it.
public struct HCGAccountUser: Equatable, Sendable {
    public let id: String
    public let email: String?
    public let displayName: String?

    public init(id: String, email: String?, displayName: String?) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
}

public enum HCGAccountState: Equatable, Sendable {
    case signedOut
    case signedIn(HCGAccountUser)
    /// The session ended on the server (expired refresh, revoked, deleted account).
    case expired(String)
}

/// Why a sign-in failed, in words a person can act on.
public enum HCGSignInError: Error, Equatable, Sendable {
    case invalidCredentials
    case emailNotConfirmed
    case rateLimited
    case offline
    case unavailable
    case other(String)

    public var message: String {
        switch self {
        case .invalidCredentials: "That email and password don't match an HCG account."
        case .emailNotConfirmed: "This HCG account's email address hasn't been confirmed yet. Use the link HCG sent you, then try again."
        case .rateLimited: "Too many attempts. Wait a minute and try again."
        case .offline: "You're offline. Connect to the internet to sign in."
        case .unavailable: "HCG sign-in is temporarily unavailable. Try again shortly."
        case .other(let text): text
        }
    }
}

/// What sign-out achieved, stated exactly.
public struct HCGSignOutOutcome: Equatable, Sendable {
    /// The identity service confirmed this session was ended (refresh token revoked).
    public let revokedOnServer: Bool
    public var message: String {
        revokedOnServer
            ? "Signed out. HCG ended this device's session. Other devices stay signed in."
            : "Signed out on this device. HCG couldn't be reached to end the session, so it ends when it expires (at most an hour). Other devices stay signed in."
    }
}

/// HCG account sign-in, as the HCG website and HCG ONE use it: the shared identity
/// service's password grant, refresh-token rotation and logout. Tokens are kept only in
/// the Keychain. The password is sent once over HTTPS and never stored.
public actor HCGAccountSession {
    public static let refreshMargin: TimeInterval = 90

    private let client: PlatformClient
    private let store: ConnectSessionStoring
    private let now: @Sendable () -> Date
    private var session: ConnectSession?
    private var user: HCGAccountUser?
    private var expiredReason: String?
    private var refreshTask: Task<ConnectSession?, Never>?
    private var listeners: [UUID: @Sendable (HCGAccountState) -> Void] = [:]

    public init(client: PlatformClient, store: ConnectSessionStoring, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.store = store
        self.now = now
    }

    public var state: HCGAccountState {
        if let user, session != nil { return .signedIn(user) }
        if let expiredReason { return .expired(expiredReason) }
        return .signedOut
    }

    /// Called whenever the account changes (sign-in, sign-out, expiry, account switch).
    public func observe(_ listener: @escaping @Sendable (HCGAccountState) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }

    private func notify() {
        let current = state
        for listener in listeners.values { listener(current) }
    }

    private var environmentTag: String { "hcg-platform:\(client.configuration.projectRef)" }

    // MARK: Restore

    /// Restores the Keychain session (if it belongs to this project) without a network call.
    public func restore() {
        guard session == nil else { return }
        guard let stored = try? store.load() else { return }
        guard stored.environment == environmentTag, let subject = stored.subject else {
            try? store.delete()
            return
        }
        session = stored
        user = HCGAccountUser(id: subject, email: stored.displayName, displayName: nil)
        notify()
    }

    // MARK: Sign in

    public func signIn(email: String, password: String) async throws -> HCGAccountUser {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else { throw HCGSignInError.invalidCredentials }
        var request = client.baseRequest(tokenURL(grant: "password"), method: "POST", token: nil)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": trimmed, "password": password])
        let object: [String: Any]
        do {
            let (data, _) = try await client.send(request)
            object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        } catch let error as PlatformError {
            throw Self.signInError(error)
        }
        let previous = user?.id
        let (newSession, newUser) = try sessionFrom(object)
        if previous != nil, previous != newUser.id {
            // A different account: nothing from the previous one may carry over.
            await endLocally()
        }
        try persist(newSession)
        session = newSession
        user = newUser
        expiredReason = nil
        notify()
        return newUser
    }

    static func signInError(_ error: PlatformError) -> HCGSignInError {
        switch error {
        case .offline, .timedOut: return .offline
        case .rateLimited: return .rateLimited
        case .unavailable: return .unavailable
        case .server(let status, let message):
            let lowered = (message ?? "").lowercased()
            if lowered.contains("email not confirmed") { return .emailNotConfirmed }
            if status == 400 || lowered.contains("invalid login") { return .invalidCredentials }
            return .other("HCG sign-in returned an error (\(status)).")
        case .unauthorized, .forbidden: return .invalidCredentials
        default: return .other(error.message)
        }
    }

    // MARK: Tokens

    /// A usable access token, refreshing first when it is close to expiry. Nil when the
    /// person must sign in again (or isn't signed in).
    public func validAccessToken() async -> String? {
        guard let current = session else { return nil }
        if current.expiresAt.timeIntervalSince(now()) > Self.refreshMargin { return current.accessToken }
        return await refreshed()?.accessToken
    }

    /// Called when the server rejected a token (HTTP 401). Refreshes once; if that fails
    /// the session is ended locally and the state becomes `.expired`.
    public func accessTokenAfterRejection(_ rejected: String) async -> String? {
        guard let current = session else { return nil }
        if current.accessToken != rejected { return current.accessToken }
        return await refreshed()?.accessToken
    }

    private func refreshed() async -> ConnectSession? {
        if let refreshTask { return await refreshTask.value }
        let task = Task<ConnectSession?, Never> { await performRefresh() }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh() async -> ConnectSession? {
        guard let current = session, let refreshToken = current.refreshToken else {
            await expire("Your HCG session ended. Sign in again.")
            return nil
        }
        var request = client.baseRequest(tokenURL(grant: "refresh_token"), method: "POST", token: nil)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        do {
            let (data, _) = try await client.send(request)
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let (newSession, newUser) = try sessionFrom(object)
            guard newUser.id == user?.id else {
                await expire("HCG returned a different account. Sign in again.")
                return nil
            }
            try? persist(newSession)
            session = newSession
            user = newUser
            return newSession
        } catch PlatformError.offline, PlatformError.timedOut, PlatformError.unavailable, PlatformError.rateLimited {
            // Temporary: keep the session; the caller reports the connection problem.
            return current.expiresAt > now() ? current : nil
        } catch {
            await expire("Your HCG session expired or was revoked. Sign in again.")
            return nil
        }
    }

    /// Asks the identity service who this token belongs to. Detects revoked sessions and
    /// deleted accounts; updates the displayed email.
    @discardableResult
    public func verifyWithServer() async -> Result<HCGAccountUser, PlatformError> {
        await verifyWithServer(retried: false)
    }

    private func verifyWithServer(retried: Bool) async -> Result<HCGAccountUser, PlatformError> {
        guard let token = await validAccessToken() else { return .failure(.unauthorized) }
        let request = client.baseRequest(client.configuration.authURL.appendingPathComponent("user"), method: "GET", token: token)
        do {
            let (data, _) = try await client.send(request)
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let verified = Self.user(from: object) else { return .failure(.contract("user")) }
            guard verified.id == user?.id else {
                await expire("HCG returned a different account. Sign in again.")
                return .failure(.unauthorized)
            }
            user = verified
            if var s = session { s.displayName = verified.email; session = s; try? persist(s) }
            notify()
            return .success(verified)
        } catch let error as PlatformError {
            // The identity service answers 401/403 for expired, revoked or unknown sessions.
            if error == .unauthorized || isForbidden(error) {
                // Retry once with a refreshed token before concluding.
                if !retried, let fresh = await accessTokenAfterRejection(token), fresh != token {
                    return await verifyWithServer(retried: true)
                }
                await expire("Your HCG session expired or was revoked. Sign in again.")
                return .failure(.unauthorized)
            }
            return .failure(error)
        } catch {
            return .failure(.other("\(error)"))
        }
    }

    private func isForbidden(_ error: PlatformError) -> Bool {
        if case .forbidden = error { return true }
        return false
    }

    // MARK: Sign out

    /// Ends this device's session on the server (scope `local`: other devices stay signed
    /// in), then deletes it from the Keychain whatever the server said.
    public func signOut() async -> HCGSignOutOutcome {
        var revoked = false
        if let token = session?.accessToken {
            var components = URLComponents(url: client.configuration.authURL.appendingPathComponent("logout"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "scope", value: "local")]
            if let url = components?.url {
                let request = client.baseRequest(url, method: "POST", token: token)
                do { _ = try await client.send(request); revoked = true }
                catch PlatformError.unauthorized { revoked = true } // already invalid on the server
                catch {}
            }
        }
        await endLocally()
        notify()
        return HCGSignOutOutcome(revokedOnServer: revoked)
    }

    /// Forgets the session on this device without contacting the server.
    public func endLocally() async {
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        user = nil
        expiredReason = nil
        try? store.delete()
    }

    private func expire(_ reason: String) async {
        await endLocally()
        expiredReason = reason
        notify()
    }

    // MARK: Parsing

    private func tokenURL(grant: String) -> URL {
        var components = URLComponents(url: client.configuration.authURL.appendingPathComponent("token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grant)]
        return components.url!
    }

    private func sessionFrom(_ object: [String: Any]) throws -> (ConnectSession, HCGAccountUser) {
        guard let access = object["access_token"] as? String, !access.isEmpty,
              let refresh = object["refresh_token"] as? String, !refresh.isEmpty,
              let userObject = object["user"] as? [String: Any], let user = Self.user(from: userObject)
        else { throw HCGSignInError.other("HCG sign-in answered in an unexpected way. Nothing was stored.") }
        let expiresAt: Date
        if let at = (object["expires_at"] as? NSNumber)?.doubleValue {
            expiresAt = Date(timeIntervalSince1970: at)
        } else {
            expiresAt = now().addingTimeInterval((object["expires_in"] as? NSNumber)?.doubleValue ?? 3600)
        }
        let session = ConnectSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt,
                                     subject: user.id, displayName: user.email, environment: environmentTag)
        return (session, user)
    }

    static func user(from object: [String: Any]) -> HCGAccountUser? {
        guard let id = object["id"] as? String, !id.isEmpty else { return nil }
        let meta = object["user_metadata"] as? [String: Any]
        let name = (meta?["display_name"] as? String) ?? (meta?["full_name"] as? String) ?? (meta?["name"] as? String)
        return HCGAccountUser(id: id, email: object["email"] as? String, displayName: name)
    }

    private func persist(_ session: ConnectSession) throws {
        do { try store.save(session) }
        catch { throw HCGSignInError.other("The session couldn't be stored securely on this device, so you weren't signed in.") }
    }
}

/// Runs a request with the person's token, retrying once after a refresh if the server
/// rejects the token. Shared by every authenticated HCG platform call.
public struct AuthorizedCaller: Sendable {
    let account: HCGAccountSession

    public init(account: HCGAccountSession) { self.account = account }

    func call<T>(_ body: @Sendable (String) async throws -> T) async throws -> T {
        guard let token = await account.validAccessToken() else { throw PlatformError.unauthorized }
        do {
            return try await body(token)
        } catch PlatformError.unauthorized {
            guard let fresh = await account.accessTokenAfterRejection(token), fresh != token else {
                throw PlatformError.unauthorized
            }
            return try await body(fresh)
        }
    }
}
