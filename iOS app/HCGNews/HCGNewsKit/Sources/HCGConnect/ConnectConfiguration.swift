import Foundation
import HCGTransport

/// HCG Connect configuration for the HCG News native client.
///
/// Nothing is built in: the app reads the `connect` object of
/// `HCGNewsConfiguration.json`. Every value must come from central HCG
/// (ERP / Executive Control Center) for a reviewed, registered HCG News native
/// client. The CardX or web client must not be reused. Until every required
/// field is present and `approvedByFounder` is true, sign-in stays disabled and
/// the app makes no identity request at all.
public struct ConnectConfiguration: Equatable, Sendable {
    /// How the provider expects refresh requests. `oauthForm` is RFC 6749 §6.
    /// `providerJSON` is the identity provider's native route (JSON body plus the
    /// provider's public `apikey` header) that HCG CardX's source documents for refresh.
    public enum RefreshFormat: String, Equatable, Sendable { case oauthForm = "oauth-form", providerJSON = "provider-json" }

    /// How sign-out is reported centrally.
    /// `rfc7009` posts the refresh token to a revocation endpoint.
    /// `providerLogout` calls the provider's logout route with the access token.
    public enum SignOutFormat: String, Equatable, Sendable { case rfc7009, providerLogout = "provider-logout" }

    public let contractVersion: String
    public let environment: String
    public let issuer: URL
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let refreshEndpoint: URL
    public let refreshFormat: RefreshFormat
    public let signOutEndpoint: URL?
    public let signOutFormat: SignOutFormat?
    public let appAccessEndpoint: URL
    public let clientID: String
    public let redirectURI: URL
    public let scopes: [String]
    /// HCG News' identifier in the central App Access registry.
    public let appIdentifier: String
    /// The identity provider's PUBLIC client key, only if central HCG confirms the
    /// gateway requires it. A key whose JWT role is not `anon` is rejected.
    public let providerPublicKey: String?
    /// Centrally defined permission name that unlocks the newsroom entry point.
    public let newsroomPermission: String?
    /// Where the newsroom entry point leads (an HCG web route). Access is enforced there.
    public let newsroomURL: URL?
    /// Use an ephemeral browser session (no shared Safari cookies). Default true.
    public let ephemeralBrowserSession: Bool
    /// Central HCG management destinations (e.g. ERP pages) shown in Administration.
    /// HTTPS HCG hosts only. Opening them never grants anything; HCG checks access there.
    public let managementLinks: [ManagementLink]

    public var callbackScheme: String { redirectURI.scheme ?? "" }
}

public struct ManagementLink: Equatable, Sendable, Identifiable {
    public let title: String
    public let url: URL
    public var id: String { url.absoluteString }

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public enum ConnectConfigurationState: Equatable, Sendable {
    case awaitingSetup
    case invalid([String])
    case ready(ConnectConfiguration)

    public var configuration: ConnectConfiguration? {
        if case .ready(let c) = self { return c }
        return nil
    }
}

public enum ConnectConfigurationLoader {
    public static let supportedContractVersions: Set<String> = ["1"]

    /// Field names, for the "missing values" list shown in Settings and the handoff document.
    public static let requiredFields = [
        "contractVersion", "environment", "issuer", "authorizationEndpoint", "tokenEndpoint",
        "appAccessEndpoint", "clientID", "redirectURI", "scopes", "appIdentifier",
    ]

    struct File: Decodable {
        struct Connect: Decodable {
            let contractVersion: String?
            let environment: String?
            let approvedByFounder: Bool?
            let issuer: String?
            let authorizationEndpoint: String?
            let tokenEndpoint: String?
            let refreshEndpoint: String?
            let refreshFormat: String?
            let signOutEndpoint: String?
            let signOutFormat: String?
            let appAccessEndpoint: String?
            let clientID: String?
            let redirectURI: String?
            let scopes: [String]?
            let appIdentifier: String?
            let providerPublicKey: String?
            let newsroomPermission: String?
            let newsroomURL: String?
            let ephemeralBrowserSession: Bool?
            let managementLinks: [Link]?
        }
        struct Link: Decodable {
            let title: String?
            let url: String?
        }
        let connect: Connect?
    }

    /// - Parameters:
    ///   - data: the configuration file, or nil when none is installed.
    ///   - expectedRedirectScheme: the callback scheme this build is prepared for
    ///     (derived from its bundle identifier). A mismatching redirect is rejected.
    public static func load(_ data: Data?, expectedRedirectScheme: String) -> ConnectConfigurationState {
        guard let data else { return .awaitingSetup }
        let forbidden = SecretGuard.forbiddenKeys(inJSON: data)
        if !forbidden.isEmpty {
            return .invalid(["The configuration contains credential fields (\(forbidden.joined(separator: ", "))). A native app is a public client and must not contain a client secret."])
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            return .invalid(["The configuration file is not valid JSON in the expected shape."])
        }
        guard let c = file.connect else { return .awaitingSetup }

        var problems: [String] = []
        func text(_ value: String?, _ name: String, required: Bool = true) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty, !value.contains("<") else {
                if required { problems.append("Missing value: connect.\(name)") }
                return nil
            }
            return value
        }
        func https(_ value: String?, _ name: String, required: Bool = true) -> URL? {
            guard let s = text(value, name, required: required) else { return nil }
            guard let url = URL(string: s), url.scheme?.lowercased() == "https", url.host != nil else {
                problems.append("connect.\(name) must be an HTTPS URL.")
                return nil
            }
            return url
        }

        let version = text(c.contractVersion, "contractVersion")
        if let version, !supportedContractVersions.contains(version) {
            problems.append("Connect contract version \(version) is not supported by this build.")
        }
        let environment = text(c.environment, "environment")
        let issuer = https(c.issuer, "issuer")
        let authorization = https(c.authorizationEndpoint, "authorizationEndpoint")
        let token = https(c.tokenEndpoint, "tokenEndpoint")
        let refresh = https(c.refreshEndpoint, "refreshEndpoint", required: false) ?? token
        let signOut = https(c.signOutEndpoint, "signOutEndpoint", required: false)
        let appAccess = https(c.appAccessEndpoint, "appAccessEndpoint")
        let clientID = text(c.clientID, "clientID")
        let appIdentifier = text(c.appIdentifier, "appIdentifier")
        let newsroomURL = https(c.newsroomURL, "newsroomURL", required: false)

        // Identity endpoints must be on the issuer's host or an HCG host.
        let identityHosts = Set([issuer?.host?.lowercased()].compactMap { $0 })
        for (name, url) in [("authorizationEndpoint", authorization), ("tokenEndpoint", token),
                            ("refreshEndpoint", refresh), ("signOutEndpoint", signOut)] {
            guard let url else { continue }
            if !(identityHosts.contains(url.host?.lowercased() ?? "") || HCGHostPolicy.isHCGHost(url.host)) {
                problems.append("connect.\(name) must be on the issuer host or an HCG host.")
            }
        }
        // Authorization decisions and the newsroom must come from HCG itself.
        if let appAccess, !HCGHostPolicy.isHCGHost(appAccess.host) {
            problems.append("connect.appAccessEndpoint must be on an HCG host.")
        }
        if let newsroomURL, !HCGHostPolicy.isHCGHost(newsroomURL.host) {
            problems.append("connect.newsroomURL must be on an HCG host.")
        }

        var redirect: URL?
        if let r = text(c.redirectURI, "redirectURI") {
            if let url = URL(string: r), let scheme = url.scheme?.lowercased(),
               scheme == expectedRedirectScheme.lowercased() {
                redirect = url
            } else {
                problems.append("connect.redirectURI must use this build's callback scheme \(expectedRedirectScheme).")
            }
        }
        let scopes = (c.scopes ?? []).filter { !$0.isEmpty && !$0.contains("<") }
        if scopes.isEmpty { problems.append("Missing value: connect.scopes") }

        let refreshFormat: ConnectConfiguration.RefreshFormat
        switch c.refreshFormat {
        case nil: refreshFormat = .oauthForm
        case let raw?:
            if let f = ConnectConfiguration.RefreshFormat(rawValue: raw) { refreshFormat = f } else {
                problems.append("connect.refreshFormat must be oauth-form or provider-json.")
                refreshFormat = .oauthForm
            }
        }
        var signOutFormat: ConnectConfiguration.SignOutFormat?
        if let raw = c.signOutFormat {
            signOutFormat = ConnectConfiguration.SignOutFormat(rawValue: raw)
            if signOutFormat == nil { problems.append("connect.signOutFormat must be rfc7009 or provider-logout.") }
        }
        if signOut != nil, signOutFormat == nil, c.signOutFormat == nil {
            problems.append("connect.signOutFormat is required when signOutEndpoint is set.")
        }

        var publicKey: String?
        if let key = text(c.providerPublicKey, "providerPublicKey", required: false) {
            if let role = SecretGuard.jwtRoleClaim(key), role != "anon" {
                problems.append("connect.providerPublicKey is a '\(role)' key. Only the public anon key may ship in an app.")
            } else {
                publicKey = key
            }
        }
        if refreshFormat == .providerJSON, publicKey == nil {
            problems.append("connect.refreshFormat provider-json requires connect.providerPublicKey.")
        }
        if c.newsroomPermission != nil, newsroomURL == nil {
            problems.append("connect.newsroomURL is required when newsroomPermission is set.")
        }
        var links: [ManagementLink] = []
        for (index, link) in (c.managementLinks ?? []).enumerated() {
            guard let title = link.title, !title.isEmpty, let raw = link.url, let url = URL(string: raw),
                  HCGHostPolicy.isTrustedHCGURL(url) else {
                problems.append("connect.managementLinks[\(index)] needs a title and an HTTPS URL on an HCG host.")
                continue
            }
            links.append(ManagementLink(title: title, url: url))
        }
        if c.approvedByFounder != true {
            problems.append("The configuration has not been approved by the founder (approvedByFounder is not true).")
        }

        guard problems.isEmpty, let version, let environment, let issuer, let authorization, let token,
              let refresh, let appAccess, let clientID, let redirect, let appIdentifier
        else { return .invalid(problems) }

        return .ready(ConnectConfiguration(
            contractVersion: version, environment: environment, issuer: issuer,
            authorizationEndpoint: authorization, tokenEndpoint: token, refreshEndpoint: refresh,
            refreshFormat: refreshFormat, signOutEndpoint: signOut, signOutFormat: signOutFormat,
            appAccessEndpoint: appAccess, clientID: clientID, redirectURI: redirect, scopes: scopes,
            appIdentifier: appIdentifier, providerPublicKey: publicKey,
            newsroomPermission: text(c.newsroomPermission, "newsroomPermission", required: false),
            newsroomURL: newsroomURL, ephemeralBrowserSession: c.ephemeralBrowserSession ?? true,
            managementLinks: links))
    }
}
