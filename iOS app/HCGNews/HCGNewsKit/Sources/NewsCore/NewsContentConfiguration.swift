import Foundation
import HCGTransport

/// Configuration for the HCG News content API.
///
/// There are NO built-in defaults: no endpoint is compiled into the app. The
/// app reads `HCGNewsConfiguration.json` (key `content`) from its bundle. Until a
/// file with every field, HTTPS HCG hosts and `approvedByFounder: true` is
/// installed, the app shows "Publication not connected".
public struct NewsContentConfiguration: Equatable, Sendable {
    /// Contract versions this build can decode.
    public static let supportedContractVersions: Set<String> = ["1"]

    /// Where the publication's content comes from.
    public enum Backend: Equatable, Sendable {
        /// The proposed HCG News content API (docs/HCG-NEWS-CONTENT-API-PROPOSAL.md).
        case contentAPI
        /// The real HCG platform: the publication's own tables, read through the shared
        /// HCG project with the public client key and row-level security.
        case hcgPlatform(HCGPlatformConfiguration)
    }

    public let backend: Backend

    public let contractVersion: String
    public let environment: String
    /// Base of the content API, e.g. a versioned path on an HCG host (to be confirmed).
    public let apiBaseURL: URL
    /// The public publication origin, used to resolve relative links in article HTML.
    public let publicationURL: URL
    public let approvedByFounder: Bool
    /// Optional newsroom (editorial write) API base, hosted by the publication.
    /// Requires an HCG Connect token; every action is authorised server-side.
    public let newsroomAPIBaseURL: URL?

    public init(contractVersion: String, environment: String, apiBaseURL: URL, publicationURL: URL,
                approvedByFounder: Bool, newsroomAPIBaseURL: URL? = nil) {
        self.backend = .contentAPI
        self.contractVersion = contractVersion
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.publicationURL = publicationURL
        self.approvedByFounder = approvedByFounder
        self.newsroomAPIBaseURL = newsroomAPIBaseURL
    }

    /// A configuration for the real HCG platform.
    public init(platform: HCGPlatformConfiguration) {
        backend = .hcgPlatform(platform)
        contractVersion = "hcg-platform-1"
        environment = platform.environment
        apiBaseURL = platform.restURL
        publicationURL = platform.publicationURL
        approvedByFounder = true
        newsroomAPIBaseURL = nil
    }

    public var platform: HCGPlatformConfiguration? {
        if case .hcgPlatform(let p) = backend { return p }
        return nil
    }
}

public enum NewsConfigurationState: Equatable, Sendable {
    /// No configuration file installed.
    case awaitingSetup
    /// A file exists but cannot be used; reasons are safe to display.
    case invalid([String])
    case ready(NewsContentConfiguration)
}

public enum NewsConfigurationLoader {
    struct File: Decodable {
        struct Content: Decodable {
            let contractVersion: String?
            let environment: String?
            let apiBaseURL: String?
            let publicationURL: String?
            let approvedByFounder: Bool?
            let newsroomAPIBaseURL: String?
        }
        struct Platform: Decodable {
            let environment: String?
            let projectURL: String?
            let publicClientKey: String?
            let websiteURL: String?
            let publicationURL: String?
            let approvedByFounder: Bool?
        }
        let content: Content?
        let hcgPlatform: Platform?
    }

    /// Validates a configuration file's data. `nil` data means no file is installed.
    public static func load(_ data: Data?) -> NewsConfigurationState {
        guard let data else { return .awaitingSetup }
        let forbidden = SecretGuard.forbiddenKeys(inJSON: data)
        if !forbidden.isEmpty {
            return .invalid(["The configuration contains credential fields (\(forbidden.joined(separator: ", "))). Native apps must not ship secrets."])
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            return .invalid(["The configuration file is not valid JSON in the expected shape."])
        }
        if let platform = file.hcgPlatform {
            var (configuration, problems) = HCGPlatformConfiguration.validate(
                environment: platform.environment, projectURL: platform.projectURL,
                publicClientKey: platform.publicClientKey, websiteURL: platform.websiteURL,
                publicationURL: platform.publicationURL)
            if platform.approvedByFounder != true {
                problems.append("The configuration has not been approved by the founder (approvedByFounder is not true).")
            }
            guard problems.isEmpty, let configuration else { return .invalid(problems) }
            return .ready(NewsContentConfiguration(platform: configuration))
        }
        guard let content = file.content else { return .awaitingSetup }

        var problems: [String] = []
        func required(_ value: String?, _ name: String) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty, !value.contains("<") else {
                problems.append("Missing value: content.\(name)")
                return nil
            }
            return value
        }
        let version = required(content.contractVersion, "contractVersion")
        let environment = required(content.environment, "environment")
        let apiString = required(content.apiBaseURL, "apiBaseURL")
        let publicationString = required(content.publicationURL, "publicationURL")

        if let version, !NewsContentConfiguration.supportedContractVersions.contains(version) {
            problems.append("Contract version \(version) is not supported by this build.")
        }
        var apiURL: URL?
        if let apiString {
            apiURL = URL(string: apiString.hasSuffix("/") ? apiString : apiString + "/")
            if !HCGHostPolicy.isTrustedHCGURL(apiURL) {
                problems.append("content.apiBaseURL must be an HTTPS URL on an HCG host.")
            }
        }
        var publicationURL: URL?
        if let publicationString {
            publicationURL = URL(string: publicationString)
            if !HCGHostPolicy.isTrustedHCGURL(publicationURL) {
                problems.append("content.publicationURL must be an HTTPS URL on an HCG host.")
            }
        }
        var newsroomURL: URL?
        if let raw = content.newsroomAPIBaseURL, !raw.contains("<"), !raw.isEmpty {
            newsroomURL = URL(string: raw.hasSuffix("/") ? raw : raw + "/")
            if !HCGHostPolicy.isTrustedHCGURL(newsroomURL) {
                problems.append("content.newsroomAPIBaseURL must be an HTTPS URL on an HCG host.")
            }
        }
        if content.approvedByFounder != true {
            problems.append("The configuration has not been approved by the founder (approvedByFounder is not true).")
        }
        guard problems.isEmpty, let version, let environment, let apiURL, let publicationURL else {
            return .invalid(problems)
        }
        return .ready(NewsContentConfiguration(
            contractVersion: version, environment: environment, apiBaseURL: apiURL,
            publicationURL: publicationURL, approvedByFounder: true, newsroomAPIBaseURL: newsroomURL))
    }
}
