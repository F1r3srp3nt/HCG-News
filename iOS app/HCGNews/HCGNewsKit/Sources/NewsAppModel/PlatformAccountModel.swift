import Foundation
import Observation
import HCGPlatform
import HCGTransport

/// The signed-in HCG account, its HCG News roles and its HCG workspaces, as HCG
/// reported them in this session. Nothing here is decided locally.
@MainActor
@Observable
public final class PlatformAccountModel {
    public enum Check<Value: Equatable & Sendable>: Equatable, Sendable {
        case notChecked
        case checking
        case ready(Value)
        case failed(String)

        public var value: Value? { if case .ready(let v) = self { return v }; return nil }
    }

    public private(set) var state: HCGAccountState = .signedOut
    public private(set) var permissions: Check<NewsroomPermissions> = .notChecked
    public private(set) var workspaces: Check<HCGWorkspaceDirectory> = .notChecked
    public private(set) var isWorking = false
    public private(set) var signInError: String?
    /// The outcome of the last sign-out, worded exactly.
    public private(set) var lastMessage: String?
    public private(set) var openingWorkspace: String?
    public private(set) var workspaceError: String?

    @ObservationIgnored public let session: HCGAccountSession
    @ObservationIgnored let roles: NewsroomRoleResolver
    @ObservationIgnored let workspaceService: HCGWorkspaceService
    @ObservationIgnored let log: LocalEventLog?
    @ObservationIgnored private var lastAccessCheck: Date?
    /// Called when the account ends or changes, so account-specific caches are cleared.
    @ObservationIgnored public var onAccountChange: (@MainActor () -> Void)?
    @ObservationIgnored private var observation: UUID?

    public static let accessRecheckInterval: TimeInterval = 60

    public init(session: HCGAccountSession, roles: NewsroomRoleResolver, workspaces: HCGWorkspaceService, log: LocalEventLog?) {
        self.session = session
        self.roles = roles
        self.workspaceService = workspaces
        self.log = log
    }

    public var user: HCGAccountUser? { if case .signedIn(let u) = state { return u }; return nil }
    public var isSignedIn: Bool { user != nil }
    /// Roles from this session's check; `.none` until HCG answered.
    public var currentPermissions: NewsroomPermissions { permissions.value ?? .none }
    public var expiredReason: String? { if case .expired(let r) = state { return r }; return nil }

    // MARK: Lifecycle

    public func restore() async {
        if observation == nil {
            observation = await session.observe { [weak self] newState in
                Task { @MainActor in self?.sessionChanged(newState) }
            }
        }
        await session.restore()
        state = await session.state
        if isSignedIn { await refreshAccess() }
    }

    private func sessionChanged(_ newState: HCGAccountState) {
        let previous = user?.id
        state = newState
        if user?.id != previous {
            clearAccountData()
        }
    }

    private func clearAccountData() {
        permissions = .notChecked
        workspaces = .notChecked
        lastAccessCheck = nil
        workspaceError = nil
        onAccountChange?()
    }

    // MARK: Sign in / out

    public func signIn(email: String, password: String) async {
        isWorking = true
        signInError = nil
        lastMessage = nil
        defer { isWorking = false }
        do {
            let previous = user?.id
            let user = try await session.signIn(email: email, password: password)
            state = .signedIn(user)
            if previous != user.id { clearAccountData() }
            await log?.record(.account, "Signed in with an HCG account")
            await refreshAccess()
        } catch let error as HCGSignInError {
            signInError = error.message
            await log?.record(.account, "Sign-in failed")
        } catch {
            signInError = "Sign-in failed."
        }
    }

    public func signOut() async {
        isWorking = true
        defer { isWorking = false }
        let outcome = await session.signOut()
        state = .signedOut
        clearAccountData()
        lastMessage = outcome.message
        await log?.record(.account, outcome.revokedOnServer ? "Signed out; session ended on HCG" : "Signed out locally; HCG not reached")
    }

    public func clearMessages() {
        signInError = nil
        lastMessage = nil
        workspaceError = nil
    }

    // MARK: Access

    /// Re-reads identity, HCG News roles and HCG workspaces from HCG.
    public func refreshAccess() async {
        guard let user else { return }
        permissions = .checking
        if workspaces.value == nil { workspaces = .checking }
        let verified = await session.verifyWithServer()
        if case .failure(let error) = verified {
            if !isSignedIn { return } // ended: state already updated through the observer
            if error == .offline || error == .timedOut {
                permissions = .failed("You're offline, so your HCG News access couldn't be checked. Newsroom tools stay closed until it can be.")
                workspaces = .failed(error.message)
                return
            }
        }
        state = await session.state
        guard let current = self.user, current.id == user.id else { clearAccountData(); return }
        do {
            let result = try await roles.permissions(userID: current.id)
            permissions = .ready(result)
            lastAccessCheck = Date()
            await log?.record(.account, "HCG News access checked: \(result.orderedRoles.map(\.title).joined(separator: ", ").ifEmpty("no newsroom role"))")
        } catch let error as PlatformError {
            permissions = .failed("HCG News access couldn't be checked: \(error.message)")
            if error == .unauthorized { state = await session.state }
        } catch {
            permissions = .failed("HCG News access couldn't be checked.")
        }
        do { workspaces = .ready(try await workspaceService.directory()) }
        catch { workspaces = .failed(error.message) }
    }

    /// Called when the app returns to the foreground, so changes made centrally (roles
    /// granted or removed, sessions revoked) apply without a restart.
    public func refreshIfStale() async {
        guard isSignedIn else { return }
        if let last = lastAccessCheck, Date().timeIntervalSince(last) < Self.accessRecheckInterval { return }
        await refreshAccess()
    }

    /// Asks HCG for a one-time link into a website workspace (e.g. the ERP). The link
    /// opens in the browser, where the website starts its own session.
    public func workspaceLink(_ target: String) async -> URL? {
        openingWorkspace = target
        workspaceError = nil
        defer { openingWorkspace = nil }
        do {
            let handoff = try await workspaceService.handoff(target: target)
            await log?.record(.account, "Opened HCG workspace \(target) with a one-time link")
            return handoff.url
        } catch {
            workspaceError = error.message
            if error == .signedOut { state = await session.state }
            if error == .denied { await refreshAccess() }
            return nil
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
