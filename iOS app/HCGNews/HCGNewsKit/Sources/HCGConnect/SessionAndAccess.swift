import Foundation
import HCGTransport

/// The stored HCG Connect session (Keychain only, device-only accessibility).
public struct ConnectSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    /// Subject identifier from the access token (display/consistency only;
    /// the server re-verifies the token on every request).
    public var subject: String?
    public var displayName: String?
    /// Configuration environment the session was issued for.
    public var environment: String
    /// Organisation the reader chose among those HCG offered (nil = HCG's default).
    public var selectedOrganizationID: String?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date, subject: String?,
                displayName: String?, environment: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.subject = subject
        self.displayName = displayName
        self.environment = environment
    }

    /// True when the access token is expired or within `leeway` of expiry.
    public func needsRefresh(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }

    // Tokens never appear in logs or debug descriptions.
    public var redactedDescription: String {
        "ConnectSession(subject: \(subject ?? "nil"), expiresAt: \(expiresAt), environment: \(environment))"
    }
}

/// OAuth token endpoint response.
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?
    let expiresAt: Double?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token"
        case expiresIn = "expires_in", expiresAt = "expires_at", tokenType = "token_type"
    }

    func expiry(now: Date) -> Date {
        if let expiresAt { return Date(timeIntervalSince1970: expiresAt) }
        // Without an expiry, assume a short life so the app re-validates soon.
        return now.addingTimeInterval(expiresIn ?? 300)
    }
}

struct OAuthErrorBody: Decodable {
    let error: String?
    let errorDescription: String?
    let errorCode: String?
    let msg: String?

    enum CodingKeys: String, CodingKey {
        case error, errorDescription = "error_description", errorCode = "error_code", msg
    }

    var code: String? { error ?? errorCode }
}

/// Reads display-only claims from a JWT access token without verifying it.
/// Never used for authorization decisions.
enum UnverifiedClaims {
    static func payload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var s = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        guard let data = Data(base64Encoded: s) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func subject(_ jwt: String) -> String? { payload(jwt)?["sub"] as? String }

    static func displayName(_ jwt: String) -> String? {
        guard let p = payload(jwt) else { return nil }
        if let name = p["name"] as? String, !name.isEmpty { return name }
        if let meta = p["user_metadata"] as? [String: Any] {
            for key in ["display_name", "full_name", "name"] {
                if let v = meta[key] as? String, !v.isEmpty { return v }
            }
        }
        return nil
    }
}

/// The central App Access decision for HCG News (PROPOSED shape, aligned with the
/// LifeOS handoff; to be confirmed by central HCG).
public struct AppAccessDecision: Codable, Equatable, Sendable {
    public enum Status: Equatable, Sendable, Codable {
        case granted, denied, revoked, unlicensed, suspended
        case unknown(String)

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw.lowercased() {
            case "granted": self = .granted
            case "denied": self = .denied
            case "revoked": self = .revoked
            case "unlicensed": self = .unlicensed
            case "suspended": self = .suspended
            default: self = .unknown(raw)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .granted: try c.encode("granted")
            case .denied: try c.encode("denied")
            case .revoked: try c.encode("revoked")
            case .unlicensed: try c.encode("unlicensed")
            case .suspended: try c.encode("suspended")
            case .unknown(let v): try c.encode(v)
            }
        }
    }

    public struct Organization: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }

    /// A licence or subscription entitlement as reported by HCG. Displayed only.
    public struct Entitlement: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let status: String
        public let validUntil: Date?
        public init(id: String, name: String, status: String, validUntil: Date?) {
            self.id = id; self.name = name; self.status = status; self.validUntil = validUntil
        }
    }

    public let appIdentifier: String
    public let subject: String
    public let organizationID: String?
    public let status: Status
    /// Permission names defined centrally. Treated as opaque strings.
    public let permissions: [String]
    public let validUntil: Date?
    public let reason: String?
    /// Identity details verified by HCG (optional; shown only when supplied).
    public let displayName: String?
    public let email: String?
    /// Organisations the subject may act for (optional). Selection is only offered when HCG lists several.
    public let organizations: [Organization]?
    public let entitlements: [Entitlement]?

    public init(appIdentifier: String, subject: String, organizationID: String? = nil, status: Status,
                permissions: [String], validUntil: Date? = nil, reason: String? = nil,
                displayName: String? = nil, email: String? = nil, organizations: [Organization]? = nil,
                entitlements: [Entitlement]? = nil) {
        self.appIdentifier = appIdentifier
        self.subject = subject
        self.organizationID = organizationID
        self.status = status
        self.permissions = permissions
        self.validUntil = validUntil
        self.reason = reason
        self.displayName = displayName
        self.email = email
        self.organizations = organizations
        self.entitlements = entitlements
    }

    /// The organisation in effect, when HCG named it.
    public var currentOrganization: Organization? {
        guard let organizationID else { return nil }
        return organizations?.first { $0.id == organizationID }
    }

    /// True only for a granted, unexpired decision that names `permission`.
    public func allows(_ permission: String, at now: Date = Date()) -> Bool {
        guard status == .granted else { return false }
        if let validUntil, validUntil <= now { return false }
        return permissions.contains(permission)
    }
}

/// Whether the newsroom entry point may be shown. Display only: the newsroom
/// itself must enforce access server-side. Signing in never grants this.
public enum NewsroomEntryPolicy {
    public static func entryURL(configuration: ConnectConfiguration?, decision: AppAccessDecision?, now: Date = Date()) -> URL? {
        guard let configuration,
              let permission = configuration.newsroomPermission,
              let url = configuration.newsroomURL,
              let decision,
              decision.appIdentifier == configuration.appIdentifier,
              decision.allows(permission, at: now)
        else { return nil }
        return url
    }
}
