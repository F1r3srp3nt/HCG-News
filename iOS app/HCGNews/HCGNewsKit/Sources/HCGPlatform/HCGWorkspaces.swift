import Foundation
import HCGTransport

/// The HCG website's workspace directory for the signed-in person
/// (`GET /api/public/mobile/workspaces`), as documented in HCG ONE's integration
/// contract. The website decides `permitted` and `available`; the app only displays it.
public struct HCGWorkspaceDirectory: Equatable, Sendable {
    public struct Workspace: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String?
        /// The website route the workspace lives at (e.g. `/erp`), as the directory reports it.
        public let route: String?
        public let permitted: Bool
        public let available: Bool

        /// The handoff target: the website route, as HCG ONE sends it. Falls back to the
        /// routes HCG ONE uses for the known workspaces.
        public var handoffTarget: String {
            if let route, route.hasPrefix("/") { return route }
            switch id {
            case "erp": return "/erp"
            case "ceo_suite": return "/control-panel"
            case "employee_suite": return "/dashboard"
            case "client_workspace": return "/client-portal"
            default: return id
            }
        }

        public var displayTitle: String {
            if let title, !title.isEmpty { return title }
            switch id {
            case "erp": return "HCG ERP"
            case "ceo_suite": return "Executive Control Center"
            case "employee_suite": return "Employee workspace"
            case "client_workspace": return "Client workspace"
            case "hcg_connect": return "HCG Connect"
            default: return id
            }
        }
    }

    public let roles: [String]
    public let workspaces: [Workspace]
    public let handoffVersion: Int?
    public let checkedAt: Date

    public func workspace(_ id: String) -> Workspace? { workspaces.first { $0.id == id } }
}

/// A one-time link that starts the person's own web session on the HCG website.
public struct HCGHandoff: Equatable, Sendable {
    public let url: URL
    public let expiresAt: Date?
}

public enum HCGWorkspaceError: Error, Equatable, Sendable {
    case signedOut
    case denied
    case expired
    case rateLimited
    case unavailable
    case offline
    case other(String)

    public var message: String {
        switch self {
        case .signedOut: "Sign in with your HCG account first."
        case .denied: "HCG hasn't given your account access to this workspace. Access is granted by HCG staff in the ERP."
        case .expired: "The one-time link expired or was already used. Try again for a fresh one."
        case .rateLimited: "Too many requests. Wait about a minute and try again."
        case .unavailable: "This HCG workspace is temporarily unavailable."
        case .offline: "You're offline."
        case .other(let text): text
        }
    }
}

/// Access to the HCG website's ERP and executive workspaces. The app never holds ERP
/// authority: it asks the website for the directory and for a one-time sign-in link,
/// and opens that link in the browser, where the website starts its own session.
public struct HCGWorkspaceService: Sendable {
    let client: PlatformClient
    let caller: AuthorizedCaller

    public init(client: PlatformClient, caller: AuthorizedCaller) {
        self.client = client
        self.caller = caller
    }

    public func directory(now: Date = Date()) async throws(HCGWorkspaceError) -> HCGWorkspaceDirectory {
        let client = self.client
        let url = client.configuration.websiteURL.appendingPathComponent("api/public/mobile/workspaces")
        let object: [String: Any]
        do {
            object = try await caller.call { token in
                var request = client.baseRequest(url, method: "GET", token: token)
                request.setValue(nil, forHTTPHeaderField: "apikey")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                guard let o = try await client.json(request) as? [String: Any] else { throw PlatformError.contract("directory") }
                return o
            }
        } catch { throw Self.map(error) }
        let workspaces = (object["workspaces"] as? [[String: Any]] ?? []).compactMap { w -> HCGWorkspaceDirectory.Workspace? in
            guard let id = w["id"] as? String else { return nil }
            return .init(id: id, title: w["title"] as? String, route: w["route"] as? String,
                         permitted: (w["permitted"] as? Bool) ?? false,
                         available: (w["available"] as? Bool) ?? false)
        }
        let integration = object["integration"] as? [String: Any]
        return HCGWorkspaceDirectory(roles: object["roles"] as? [String] ?? [], workspaces: workspaces,
                                     handoffVersion: (integration?["version"] as? NSNumber)?.intValue, checkedAt: now)
    }

    /// Requests a single-use link (valid about 60 seconds) for a website route such as `/erp`.
    public func handoff(target: String) async throws(HCGWorkspaceError) -> HCGHandoff {
        let client = self.client
        let url = client.configuration.websiteURL.appendingPathComponent("api/public/mobile/handoff")
        let object: [String: Any]
        do {
            object = try await caller.call { token in
                var request = client.baseRequest(url, method: "POST", token: token)
                request.setValue(nil, forHTTPHeaderField: "apikey")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["target": target])
                guard let o = try await client.json(request) as? [String: Any] else { throw PlatformError.contract("handoff") }
                return o
            }
        } catch { throw Self.map(error) }
        guard let raw = object["url"] as? String, let link = URL(string: raw),
              HCGHostPolicy.isTrustedHCGURL(link) else {
            throw .other("HCG returned a link that isn't on an HCG website, so it wasn't opened.")
        }
        let expiry = ((object["expiresAt"] as? String) ?? (object["expires_at"] as? String)).flatMap(HCGJSON.parseDate)
        return HCGHandoff(url: link, expiresAt: expiry)
    }

    static func map(_ error: Error) -> HCGWorkspaceError {
        guard let error = error as? PlatformError else { return .other("\(error)") }
        switch error {
        case .unauthorized: return .signedOut
        case .forbidden: return .denied
        case .notFound: return .expired
        case .rateLimited: return .rateLimited
        case .unavailable: return .unavailable
        case .offline, .timedOut: return .offline
        default: return .other(error.message)
        }
    }
}
