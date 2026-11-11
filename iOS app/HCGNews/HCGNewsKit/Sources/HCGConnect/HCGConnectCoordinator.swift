import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport

/// Presents the system authentication browser (ASWebAuthenticationSession on iOS).
/// Never an embedded web view.
public protocol BrowserAuthenticating: Sendable {
    func authenticate(url: URL, callbackScheme: String, ephemeral: Bool) async throws -> URL
}

public enum BrowserAuthenticationError: Error, Equatable, Sendable {
    case cancelled
    case unavailable(String)
}

/// Secure session persistence. The app uses the Keychain implementation.
public protocol ConnectSessionStoring: Sendable {
    func load() throws -> ConnectSession?
    func save(_ session: ConnectSession) throws
    func delete() throws
}

public enum AuthenticationStatus: Equatable, Sendable {
    /// Configuration not ready: no identity request is ever made.
    case unavailable
    case signedOut
    case signingIn
    case signedIn(subject: String?, displayName: String?)
    /// The session ended (refresh refused). The reader must sign in again.
    case expired
}

public enum AccessStatus: Equatable, Sendable {
    case notChecked
    case checking
    /// The central decision, as returned. `granted` does not by itself unlock anything;
    /// features check specific permission names.
    case decided(AppAccessDecision)
    /// The App Access endpoint refused (HTTP 403) without a readable decision.
    case refused(reason: String?)
    case failed(String)
}

/// Last notable event, for a one-line message in Settings.
public enum ConnectEvent: Equatable, Sendable {
    case cancelled
    case denied(String?)
    case failed(String)
    case expired
    case revoked
    case signedOut(SignOutReport)
}

public struct SignOutReport: Equatable, Sendable {
    public enum Central: Equatable, Sendable {
        /// No sign-out endpoint configured: only this device's session was removed.
        case notConfigured
        /// The endpoint acknowledged the request.
        case acknowledged
        case failed(String)
    }
    public let localSessionCleared: Bool
    public let central: Central
}

public struct ConnectStatus: Equatable, Sendable {
    public let configuration: ConnectConfigurationState
    public let authentication: AuthenticationStatus
    public let access: AccessStatus
    public let lastEvent: ConnectEvent?
    public let newsroomURL: URL?
}

/// Coordinates HCG Connect sign-in for HCG News.
///
/// - Refuses everything unless the configuration is `.ready`.
/// - Tokens live only in the injected secure store; never logged.
/// - Refresh is single-flight (refresh-token rotation makes concurrent refreshes unsafe).
/// - Authorization comes only from the central App Access decision fetched in this run.
public actor HCGConnectCoordinator {
    private let configurationState: ConnectConfigurationState
    private let browser: BrowserAuthenticating
    private let store: ConnectSessionStoring
    private let transport: HTTPTransport
    private let userAgent: String
    private let now: @Sendable () -> Date

    private var session: ConnectSession?
    private var authentication: AuthenticationStatus
    private var access: AccessStatus = .notChecked
    private var lastEvent: ConnectEvent?
    private var refreshTask: Task<ConnectSession?, Never>?

    public init(configuration: ConnectConfigurationState,
                browser: BrowserAuthenticating,
                store: ConnectSessionStoring,
                transport: HTTPTransport,
                userAgent: String,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.configurationState = configuration
        self.browser = browser
        self.store = store
        self.transport = transport
        self.userAgent = userAgent
        self.now = now
        self.authentication = configuration.configuration == nil ? .unavailable : .signedOut
    }

    private var configuration: ConnectConfiguration? { configurationState.configuration }

    public func status() -> ConnectStatus {
        var decision: AppAccessDecision?
        if case .decided(let d) = access { decision = d }
        return ConnectStatus(
            configuration: configurationState, authentication: authentication, access: access,
            lastEvent: lastEvent,
            newsroomURL: NewsroomEntryPolicy.entryURL(configuration: configuration, decision: decision, now: now()))
    }

    // MARK: Restore

    /// Restores a stored session for the same environment. Does not grant anything:
    /// App Access is re-checked from the server.
    public func restore() {
        guard let configuration else { return }
        guard let stored = try? store.load() else { return }
        guard stored.environment == configuration.environment else {
            try? store.delete()
            return
        }
        session = stored
        authentication = .signedIn(subject: stored.subject, displayName: stored.displayName)
    }

    // MARK: Sign-in

    public func signIn() async {
        guard let configuration else { return }
        if case .signingIn = authentication { return }
        authentication = .signingIn
        lastEvent = nil
        let attempt = AuthorizationAttempt(configuration: configuration)
        do {
            let callback = try await browser.authenticate(
                url: attempt.url, callbackScheme: configuration.callbackScheme,
                ephemeral: configuration.ephemeralBrowserSession)
            let code = try AuthorizationCallback.code(from: callback, attempt: attempt, configuration: configuration)
            let tokens = try await exchange(code: code, verifier: attempt.pkce.verifier, configuration: configuration)
            let newSession = makeSession(tokens, previous: nil, configuration: configuration)
            try persist(newSession)
            session = newSession
            authentication = .signedIn(subject: newSession.subject, displayName: newSession.displayName)
            access = .notChecked
            await checkAppAccess()
        } catch BrowserAuthenticationError.cancelled {
            authentication = .signedOut
            lastEvent = .cancelled
        } catch CallbackError.accessDenied(let reason) {
            authentication = .signedOut
            lastEvent = .denied(reason)
        } catch {
            authentication = .signedOut
            lastEvent = .failed(Self.describe(error))
        }
    }

    // MARK: Tokens

    /// A currently valid access token, refreshing once if needed. Nil when signed out,
    /// expired, or offline with an expired token.
    public func validAccessToken() async -> String? {
        guard configuration != nil, let current = session else { return nil }
        if !current.needsRefresh(now: now()) { return current.accessToken }
        return await refreshed()?.accessToken
    }

    private func refreshed() async -> ConnectSession? {
        if let refreshTask { return await refreshTask.value }
        let task = Task { await self.performRefresh() }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh() async -> ConnectSession? {
        guard let configuration, let current = session else { return nil }
        guard let refreshToken = current.refreshToken else {
            endSession(event: .expired)
            return nil
        }
        do {
            let tokens = try await refresh(refreshToken, configuration: configuration)
            let renewed = makeSession(tokens, previous: current, configuration: configuration)
            try persist(renewed)
            session = renewed
            return renewed
        } catch ConnectError.rejected {
            endSession(event: .expired)
            return nil
        } catch {
            // Offline or temporary failure: keep the session; the token is still
            // usable only if it has not actually expired.
            return current.expiresAt > now() ? current : nil
        }
    }

    // MARK: App Access

    public func checkAppAccess() async {
        guard let configuration, session != nil else { return }
        access = .checking
        for attempt in 0..<2 {
            guard let token = await validAccessToken() else {
                if session == nil { access = .notChecked } else { access = .failed("No valid session to check access.") }
                return
            }
            var components = URLComponents(url: configuration.appAccessEndpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "app", value: configuration.appIdentifier)]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            if let key = configuration.providerPublicKey { request.setValue(key, forHTTPHeaderField: "apikey") }
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch {
                access = .failed("HCG Connect could not be reached.")
                return
            }
            switch response.statusCode {
            case 200..<300:
                guard let decision = try? HCGJSON.makeDecoder().decode(AppAccessDecision.self, from: data) else {
                    access = .failed("The App Access response did not match the agreed contract.")
                    return
                }
                guard decision.appIdentifier == configuration.appIdentifier,
                      session?.subject == nil || decision.subject == session?.subject
                else {
                    access = .failed("The App Access response was for a different app or account.")
                    return
                }
                if decision.status == .revoked {
                    endSession(event: .revoked)
                    return
                }
                access = .decided(decision)
                return
            case 401 where attempt == 0:
                // Force one refresh, then retry.
                if var current = session {
                    current.expiresAt = .distantPast
                    session = current
                }
                continue
            case 401:
                endSession(event: .expired)
                return
            case 403:
                if let decision = try? HCGJSON.makeDecoder().decode(AppAccessDecision.self, from: data),
                   decision.appIdentifier == configuration.appIdentifier {
                    if decision.status == .revoked { endSession(event: .revoked); return }
                    access = .decided(decision)
                } else {
                    access = .refused(reason: (try? JSONDecoder().decode(OAuthErrorBody.self, from: data))?.msg)
                }
                return
            case 429:
                access = .failed("HCG Connect is rate limiting requests. Try again in a minute.")
                return
            default:
                access = .failed("HCG Connect answered with status \(response.statusCode).")
                return
            }
        }
    }

    // MARK: Sign-out

    /// Removes the session from this device and asks the central service to end it
    /// when a sign-out endpoint is configured. The report states what actually happened;
    /// it never claims global logout.
    @discardableResult
    public func signOut() async -> SignOutReport {
        guard let current = session else {
            return SignOutReport(localSessionCleared: true, central: .notConfigured)
        }
        var central: SignOutReport.Central = .notConfigured
        if let configuration, let endpoint = configuration.signOutEndpoint, let format = configuration.signOutFormat {
            central = await centralSignOut(current, endpoint: endpoint, format: format, configuration: configuration)
        }
        let cleared = (try? store.delete()) != nil
        session = nil
        authentication = configuration == nil ? .unavailable : .signedOut
        access = .notChecked
        let report = SignOutReport(localSessionCleared: cleared, central: central)
        lastEvent = .signedOut(report)
        return report
    }

    // MARK: Internals

    enum ConnectError: Error {
        /// The provider refused the grant (invalid_grant etc.).
        case rejected(String)
        case transport
        case contract(String)
        case storage
    }

    private func endSession(event: ConnectEvent) {
        try? store.delete()
        session = nil
        authentication = event == .expired ? .expired : .signedOut
        access = .notChecked
        lastEvent = event
    }

    private func persist(_ session: ConnectSession) throws {
        do { try store.save(session) } catch { throw ConnectError.storage }
    }

    private func makeSession(_ tokens: TokenResponse, previous: ConnectSession?, configuration: ConnectConfiguration) -> ConnectSession {
        ConnectSession(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken ?? previous?.refreshToken,
            expiresAt: tokens.expiry(now: now()),
            subject: UnverifiedClaims.subject(tokens.accessToken) ?? previous?.subject,
            displayName: UnverifiedClaims.displayName(tokens.accessToken) ?? previous?.displayName,
            environment: configuration.environment)
    }

    private func exchange(code: String, verifier: String, configuration: ConnectConfiguration) async throws -> TokenResponse {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let key = configuration.providerPublicKey { request.setValue(key, forHTTPHeaderField: "apikey") }
        request.httpBody = Self.formBody([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", configuration.redirectURI.absoluteString),
            ("client_id", configuration.clientID),
            ("code_verifier", verifier),
        ])
        return try await tokenCall(request)
    }

    private func refresh(_ refreshToken: String, configuration: ConnectConfiguration) async throws -> TokenResponse {
        var request: URLRequest
        switch configuration.refreshFormat {
        case .oauthForm:
            request = URLRequest(url: configuration.refreshEndpoint)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody([
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken),
                ("client_id", configuration.clientID),
            ])
        case .providerJSON:
            var components = URLComponents(url: configuration.refreshEndpoint, resolvingAgainstBaseURL: false)!
            if !(components.queryItems ?? []).contains(where: { $0.name == "grant_type" }) {
                components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "grant_type", value: "refresh_token")]
            }
            request = URLRequest(url: components.url!)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let key = configuration.providerPublicKey { request.setValue(key, forHTTPHeaderField: "apikey") }
        return try await tokenCall(request)
    }

    private func tokenCall(_ request: URLRequest) async throws -> TokenResponse {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw ConnectError.transport
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = try? JSONDecoder().decode(OAuthErrorBody.self, from: data)
            if (400...401).contains(response.statusCode) {
                throw ConnectError.rejected(body?.code ?? "status \(response.statusCode)")
            }
            throw ConnectError.contract("Token endpoint answered with status \(response.statusCode).")
        }
        guard let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data), !tokens.accessToken.isEmpty else {
            throw ConnectError.contract("The token response did not contain an access token.")
        }
        if let type = tokens.tokenType, type.lowercased() != "bearer" {
            throw ConnectError.contract("Unsupported token type.")
        }
        return tokens
    }

    private func centralSignOut(_ session: ConnectSession, endpoint: URL,
                                format: ConnectConfiguration.SignOutFormat,
                                configuration: ConnectConfiguration) async -> SignOutReport.Central {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let key = configuration.providerPublicKey { request.setValue(key, forHTTPHeaderField: "apikey") }
        switch format {
        case .rfc7009:
            let token = session.refreshToken ?? session.accessToken
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody([
                ("token", token),
                ("token_type_hint", session.refreshToken == nil ? "access_token" : "refresh_token"),
                ("client_id", configuration.clientID),
            ])
        case .providerLogout:
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await transport.send(request)
            // RFC 7009 §2.2: 200 for valid and already-invalid tokens alike.
            return (200..<300).contains(response.statusCode)
                ? .acknowledged
                : .failed("Sign-out endpoint answered with status \(response.statusCode).")
        } catch {
            return .failed("The sign-out endpoint could not be reached.")
        }
    }

    static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case CallbackError.stateMismatch:
            return "The sign-in response could not be verified and was discarded."
        case CallbackError.unexpectedRedirect:
            return "The sign-in returned to an unexpected address and was discarded."
        case CallbackError.providerError(let code, _):
            return "HCG Connect reported an error (\(code))."
        case CallbackError.missingCode:
            return "HCG Connect did not return an authorization code."
        case BrowserAuthenticationError.unavailable(let reason):
            return "The sign-in browser could not be opened (\(reason))."
        case ConnectError.rejected(let code):
            return "HCG Connect refused the sign-in (\(code))."
        case ConnectError.transport:
            return "HCG Connect could not be reached."
        case ConnectError.contract(let message):
            return message
        case ConnectError.storage:
            return "The session could not be stored securely on this device."
        default:
            return "Sign-in failed."
        }
    }
}
