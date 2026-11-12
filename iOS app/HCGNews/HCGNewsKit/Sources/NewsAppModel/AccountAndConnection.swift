import Foundation
import Observation
import NewsCore
import HCGConnect

// MARK: - Account

@MainActor
@Observable
public final class AccountModel {
    public private(set) var status: ConnectStatus?
    public private(set) var isWorking = false
    private let coordinator: HCGConnectCoordinator
    private let log: LocalEventLog?

    public init(coordinator: HCGConnectCoordinator, log: LocalEventLog? = nil) {
        self.coordinator = coordinator
        self.log = log
    }

    public func refresh() async { status = await coordinator.status() }

    public func restore() async {
        await coordinator.restore()
        await refresh()
        if case .signedIn? = status?.authentication {
            await coordinator.checkAppAccess()
            await refresh()
        }
    }

    public func signIn() async {
        isWorking = true
        defer { isWorking = false }
        await coordinator.signIn()
        await refresh()
        await log?.record(.account, "Sign-in attempt: \(Self.describe(status?.authentication))")
    }

    public func checkAccess() async {
        isWorking = true
        defer { isWorking = false }
        await coordinator.checkAppAccess()
        await refresh()
    }

    public func selectOrganization(_ id: String?) async {
        isWorking = true
        defer { isWorking = false }
        await coordinator.selectOrganization(id)
        await refresh()
        await log?.record(.account, "Organisation selection changed")
    }

    public func signOut() async {
        isWorking = true
        defer { isWorking = false }
        await coordinator.signOut()
        await refresh()
        await log?.record(.account, "Signed out on this device")
    }

    public func accessToken() async -> String? { await coordinator.validAccessToken() }

    /// The decision from HCG in this session, if any.
    public var decision: AppAccessDecision? {
        if case .decided(let d)? = status?.access { return d }
        return nil
    }

    public var isSignedIn: Bool {
        if case .signedIn? = status?.authentication { return true }
        return false
    }

    /// True only when HCG granted HCG News access in this session (and, if a newsroom
    /// permission is configured, named it). Never inferred locally.
    public func centralAccessGranted(permission: String?) -> Bool {
        guard let decision, decision.status == .granted else { return false }
        if let validUntil = decision.validUntil, validUntil <= Date() { return false }
        guard let permission else { return true }
        return decision.allows(permission)
    }

    public var configurationProblems: [String] {
        switch status?.configuration {
        case .awaitingSetup?: return ["No HCG Connect configuration is installed."]
        case .invalid(let problems)?: return problems
        default: return []
        }
    }

    static func describe(_ auth: AuthenticationStatus?) -> String {
        switch auth {
        case .signedIn?: return "signed in"
        case .signedOut?: return "signed out"
        case .expired?: return "expired"
        case .signingIn?: return "in progress"
        case .unavailable?, nil: return "unavailable"
        }
    }
}

// MARK: - Connection checks

@MainActor
@Observable
public final class ConnectionModel {
    public enum PublicationStatus: Equatable, Sendable {
        case notConfigured
        case invalid([String])
        /// Configuration installed, not yet checked in this session.
        case configured(environment: String)
        case checking
        /// The publication answered with a supported contract.
        case verified(environment: String, at: Date, capabilities: NewsCapabilities)
        case failed(UserFacingError, at: Date)
    }

    public enum ConnectStatus: Equatable, Sendable {
        case notConfigured
        case invalid([String])
        case configured(environment: String)
        case checking
        /// The sign-in service answered. Sign-in itself is not proven.
        case reachable(environment: String, at: Date)
        case unreachable(String, at: Date)
        /// Signed in and HCG returned an App Access decision in this session.
        case verified(environment: String, at: Date)
    }

    public private(set) var publication: PublicationStatus
    public private(set) var connect: ConnectStatus

    private let service: NewsService
    private let coordinator: HCGConnectCoordinator
    private let publicationState: NewsConfigurationState
    private let connectState: ConnectConfigurationState
    private let log: LocalEventLog?

    public init(service: NewsService, coordinator: HCGConnectCoordinator,
                publicationState: NewsConfigurationState, connectState: ConnectConfigurationState, log: LocalEventLog? = nil) {
        self.service = service
        self.coordinator = coordinator
        self.publicationState = publicationState
        self.connectState = connectState
        self.log = log
        switch publicationState {
        case .awaitingSetup: publication = .notConfigured
        case .invalid(let p): publication = .invalid(p)
        case .ready(let c): publication = .configured(environment: c.environment)
        }
        switch connectState {
        case .awaitingSetup: connect = .notConfigured
        case .invalid(let p): connect = .invalid(p)
        case .ready(let c): connect = .configured(environment: c.environment)
        }
    }

    public func checkPublication() async {
        guard case .ready(let c) = publicationState else { return }
        publication = .checking
        do {
            let caps = try await service.verifyConnection()
            publication = .verified(environment: c.environment, at: Date(), capabilities: caps)
            await log?.record(.connection, "Publication verified (\(c.environment))")
        } catch {
            let failure = UserFacingError(error)
            publication = .failed(failure, at: Date())
            await log?.record(.connection, "Publication check failed: \(failure.title)")
        }
    }

    public func checkConnect() async {
        guard case .ready(let c) = connectState else { return }
        connect = .checking
        let status = await coordinator.status()
        if case .signedIn = status.authentication, case .decided = status.access {
            connect = .verified(environment: c.environment, at: Date())
            return
        }
        switch await coordinator.checkReachability() {
        case .reachable:
            connect = .reachable(environment: c.environment, at: Date())
            await log?.record(.connection, "Sign-in service reachable (\(c.environment))")
        case .unreachable(let message):
            connect = .unreachable(message, at: Date())
            await log?.record(.connection, "Sign-in service unreachable")
        case .notConfigured:
            connect = .notConfigured
        }
    }

    public func checkAll() async {
        await checkPublication()
        await checkConnect()
    }

    /// Short text for diagnostics.
    public var publicationSummary: String {
        switch publication {
        case .notConfigured: "not configured"
        case .invalid: "invalid configuration"
        case .configured: "configured, not checked"
        case .checking: "checking"
        case .verified(_, let at, _): "verified \(at)"
        case .failed(let e, let at): "failed (\(e.title)) \(at)"
        }
    }

    public var connectSummary: String {
        switch connect {
        case .notConfigured: "not configured"
        case .invalid: "invalid configuration"
        case .configured: "configured, not checked"
        case .checking: "checking"
        case .reachable(_, let at): "reachable (sign-in not verified) \(at)"
        case .unreachable(let m, let at): "unreachable: \(m) \(at)"
        case .verified(_, let at): "verified by sign-in \(at)"
        }
    }
}
