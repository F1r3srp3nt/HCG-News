import Foundation
import HCGTransport

/// Where the real HCG services live, and the public client key the HCG website
/// and HCG ONE already ship.
///
/// Discovered from the live publication and the HCG ONE integration contract
/// (see docs/INTEGRATION-REPORT.md):
/// - identity, the newsroom tables (`news_*`), row-level security and media storage are
///   the shared HCG project at `https://<ref>.supabase.co`;
/// - the mobile integration routes (workspace directory, session handoff) are on the
///   HCG website.
///
/// The client key must be the project's **anon** key: a public key whose access is
/// limited by sign-in and row-level security. A service-role key, or a key for any
/// other project, is refused.
public struct HCGPlatformConfiguration: Equatable, Sendable {
    /// The shared HCG identity project. Configuration for any other project is refused,
    /// so an imported file cannot point the app at a look-alike backend.
    public static let knownProjectRefs: Set<String> = ["qggdyzoydveafkmjgkpq"]

    public let environment: String
    public let projectURL: URL
    public let publicClientKey: String
    /// The HCG website (mobile integration routes, ERP).
    public let websiteURL: URL
    /// The public publication origin (canonical article links, relative links in bodies).
    public let publicationURL: URL

    public init(environment: String, projectURL: URL, publicClientKey: String, websiteURL: URL, publicationURL: URL) {
        self.environment = environment
        self.projectURL = projectURL
        self.publicClientKey = publicClientKey
        self.websiteURL = websiteURL
        self.publicationURL = publicationURL
    }

    public var projectRef: String { String(projectURL.host?.split(separator: ".").first ?? "") }
    public var restURL: URL { projectURL.appendingPathComponent("rest/v1") }
    public var authURL: URL { projectURL.appendingPathComponent("auth/v1") }
    public var storageURL: URL { projectURL.appendingPathComponent("storage/v1") }

    /// Validates raw values. Returns the configuration, or the problems (safe to display).
    public static func validate(environment: String?, projectURL: String?, publicClientKey: String?,
                                websiteURL: String?, publicationURL: String?) -> (HCGPlatformConfiguration?, [String]) {
        var problems: [String] = []
        func required(_ value: String?, _ name: String) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty, !value.contains("<") else {
                problems.append("Missing value: hcgPlatform.\(name)")
                return nil
            }
            return value.trimmingCharacters(in: .whitespaces)
        }
        let env = required(environment, "environment")
        let projectString = required(projectURL, "projectURL")
        let key = required(publicClientKey, "publicClientKey")
        let websiteString = required(websiteURL, "websiteURL")
        let publicationString = required(publicationURL, "publicationURL")

        var project: URL?
        var ref: String?
        if let projectString {
            let url = URL(string: projectString.hasSuffix("/") ? String(projectString.dropLast()) : projectString)
            let host = url?.host?.lowercased() ?? ""
            let parts = host.split(separator: ".")
            if url?.scheme?.lowercased() != "https" || parts.count != 3 || !host.hasSuffix(".supabase.co")
                || !(url?.path ?? "").isEmpty && url?.path != "/" {
                problems.append("hcgPlatform.projectURL must be https://<project>.supabase.co.")
            } else if !knownProjectRefs.contains(String(parts[0])) {
                problems.append("hcgPlatform.projectURL is not the shared HCG identity project.")
            } else {
                project = url
                ref = String(parts[0])
            }
        }
        if let key {
            switch publicKeyProblem(key, expectedRef: ref) {
            case .some(let problem): problems.append(problem)
            case .none: break
            }
        }
        var website: URL?
        if let websiteString {
            website = URL(string: websiteString)
            if !HCGHostPolicy.isTrustedHCGURL(website) { problems.append("hcgPlatform.websiteURL must be an HTTPS URL on an HCG host.") }
        }
        var publication: URL?
        if let publicationString {
            publication = URL(string: publicationString)
            if !HCGHostPolicy.isTrustedHCGURL(publication) { problems.append("hcgPlatform.publicationURL must be an HTTPS URL on an HCG host.") }
        }
        guard problems.isEmpty, let env, let project, let key, let website, let publication else { return (nil, problems) }
        return (HCGPlatformConfiguration(environment: env, projectURL: project, publicClientKey: key,
                                         websiteURL: website, publicationURL: publication), [])
    }

    /// Nil when `key` is an acceptable public client key for the project.
    static func publicKeyProblem(_ key: String, expectedRef: String?) -> String? {
        if key.hasPrefix("sb_secret_") { return "hcgPlatform.publicClientKey is a secret key. Native apps must only use the public (anon) key." }
        if key.hasPrefix("sb_publishable_") { return nil }
        guard let claims = SecretGuard.jwtClaims(key) else {
            return "hcgPlatform.publicClientKey is not a recognised public client key."
        }
        guard (claims["role"] as? String) == "anon" else {
            return "hcgPlatform.publicClientKey is not an anon key. Service-role and other privileged keys are refused."
        }
        if let expectedRef, let keyRef = claims["ref"] as? String, keyRef != expectedRef {
            return "hcgPlatform.publicClientKey belongs to a different project."
        }
        return nil
    }
}
