import Foundation
import HCGTransport
import NewsCore
import HCGConnect

/// The two independent configurations.
public enum ConfigurationKind: String, Sendable, CaseIterable, Identifiable {
    /// The HCG News content (publication) API.
    case publication
    /// HCG Connect sign-in and App Access.
    case connect

    public var id: String { rawValue }
    /// Top-level key in the JSON file.
    public var sectionKey: String { self == .publication ? "content" : "connect" }
    /// Accepted top-level keys, in order of preference. A publication is either the HCG
    /// platform (`hcgPlatform`) or the proposed content API (`content`).
    public var sectionKeys: [String] { self == .publication ? ["hcgPlatform", "content"] : ["connect"] }
    public var title: String { self == .publication ? "Publication" : "HCG Connect" }
}

/// Where the active configuration came from.
public enum ConfigurationSource: Equatable, Sendable {
    /// Imported by the user through Files, at the given time.
    case imported(Date)
    /// Shipped inside the app bundle.
    case bundled
    /// Nothing installed.
    case none
}

/// What an import would change, shown before anything is applied.
public struct ConfigurationImportPreview: Equatable, Sendable {
    public let kind: ConfigurationKind
    public let environment: String?
    /// Human-readable destinations, e.g. "Content API — news.hakmicapitalgroup.com".
    public let destinations: [String]
    /// Empty when valid. Shown verbatim.
    public let problems: [String]
    /// Informational notes (e.g. "The file also contains an HCG Connect section").
    public let notes: [String]
    /// True when applying would change the signed-in identity's configuration,
    /// which signs the reader out and clears account-specific data.
    public let changesIdentity: Bool
    /// The normalised single-section document that `apply` writes.
    let normalized: Data?

    public var isValid: Bool { problems.isEmpty && normalized != nil }
}

public enum ConfigurationStoreError: Error, Equatable, Sendable {
    case invalidPreview
    case writeFailed
}

/// Result of applying or removing a configuration.
public struct ConfigurationChange: Equatable, Sendable {
    public let kind: ConfigurationKind
    /// True when the HCG Connect identity configuration changed: the caller must
    /// remove the stored session and account-specific caches.
    public let identityChanged: Bool
}

/// Persists imported configurations in Application Support, separately per kind.
///
/// - Import is two-step: `preview` (validate, no side effects) then `apply`.
/// - `apply` writes atomically and keeps the previous file, so a failed write
///   leaves the old configuration active.
/// - `remove` deletes the imported file; the bundled configuration (if any)
///   becomes active again.
/// - Secrets and privileged keys are rejected by the shared loaders.
public actor ConfigurationStore {
    private let directory: URL
    private let bundled: Data?
    private let expectedRedirectScheme: String

    public init(directory: URL, bundled: Data?, expectedRedirectScheme: String) {
        self.directory = directory
        self.bundled = bundled
        self.expectedRedirectScheme = expectedRedirectScheme
    }

    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("HCGNews/Configuration", isDirectory: true)
    }

    private func fileURL(_ kind: ConfigurationKind) -> URL {
        directory.appendingPathComponent("\(kind.rawValue).json")
    }

    private func previousURL(_ kind: ConfigurationKind) -> URL {
        directory.appendingPathComponent("\(kind.rawValue).previous.json")
    }

    // MARK: Reading

    /// The configuration document in effect for `kind` (imported, else bundled), wrapped
    /// as `{ "<sectionKey>": {...} }`, plus its source.
    public func effective(_ kind: ConfigurationKind) -> (data: Data?, source: ConfigurationSource) {
        let url = fileURL(kind)
        if let data = try? Data(contentsOf: url) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (data, .imported((attributes?[.modificationDate] as? Date) ?? Date()))
        }
        if let bundled, let entry = Self.section(kind, in: bundled) {
            return (Self.wrap(entry.key, entry.value), .bundled)
        }
        return (nil, .none)
    }

    public func publicationState() -> (NewsConfigurationState, ConfigurationSource) {
        let (data, source) = effective(.publication)
        return (NewsConfigurationLoader.load(data), source)
    }

    public func connectState() -> (ConnectConfigurationState, ConfigurationSource) {
        let (data, source) = effective(.connect)
        return (ConnectConfigurationLoader.load(data, expectedRedirectScheme: expectedRedirectScheme), source)
    }

    // MARK: Import

    /// Validates a file for `kind` without changing anything.
    public func preview(_ data: Data, as kind: ConfigurationKind) -> ConfigurationImportPreview {
        func invalid(_ problems: [String]) -> ConfigurationImportPreview {
            ConfigurationImportPreview(kind: kind, environment: nil, destinations: [], problems: problems,
                                       notes: [], changesIdentity: false, normalized: nil)
        }
        guard data.count <= 256 * 1024 else { return invalid(["The file is too large to be a configuration file."]) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return invalid(["The file is not a JSON object."])
        }
        // Secrets anywhere in the file reject the whole file, even in the other section.
        let forbidden = SecretGuard.forbiddenKeys(inJSON: data)
        if !forbidden.isEmpty {
            return invalid(["The file contains credential fields (\(forbidden.joined(separator: ", "))). A native app is a public client: client secrets, passwords and service-role keys must never be installed."])
        }
        var notes: [String] = []
        let section: Any
        var sectionKey = kind.sectionKey
        let allKeys = ConfigurationKind.publication.sectionKeys + ConfigurationKind.connect.sectionKeys
        if let entry = Self.section(kind, in: object) {
            section = entry.value
            sectionKey = entry.key
            let other: ConfigurationKind = kind == .publication ? .connect : .publication
            if other.sectionKeys.contains(where: { object[$0] != nil }) {
                notes.append("The file also contains a \(other.title) section. It is not imported here; import it separately under \(other.title).")
            }
        } else if !allKeys.contains(where: { object[$0] != nil }) {
            section = object   // A bare section object.
        } else {
            return invalid(["The file has no \"\(kind.sectionKey)\" section for \(kind.title)."])
        }
        guard let sectionObject = section as? [String: Any],
              let normalized = try? JSONSerialization.data(withJSONObject: [sectionKey: sectionObject], options: [.sortedKeys])
        else { return invalid(["The \(kind.title) section is not a JSON object."]) }

        switch kind {
        case .publication:
            switch NewsConfigurationLoader.load(normalized) {
            case .ready(let c) where c.platform != nil:
                let p = c.platform!
                return ConfigurationImportPreview(
                    kind: kind, environment: c.environment,
                    destinations: ["HCG platform — \(p.projectURL.host ?? "?") (shared HCG identity and newsroom)",
                                   "Publication — \(p.publicationURL.host ?? "?")",
                                   "HCG website — \(p.websiteURL.host ?? "?")",
                                   "Sign-in — your HCG account (email and password)"],
                    problems: [], notes: notes + ["This replaces how the app signs in: HCG accounts sign in directly, the same way as on the HCG website and in HCG ONE."],
                    changesIdentity: false, normalized: normalized)
            case .ready(let c):
                var destinations = ["Content API — \(c.apiBaseURL.host ?? "?")\(c.apiBaseURL.path)",
                                    "Publication — \(c.publicationURL.host ?? "?")",
                                    "Contract version \(c.contractVersion)"]
                if let newsroom = c.newsroomAPIBaseURL {
                    destinations.append("Newsroom API — \(newsroom.host ?? "?")\(newsroom.path)")
                }
                return ConfigurationImportPreview(
                    kind: kind, environment: c.environment,
                    destinations: destinations,
                    problems: [], notes: notes, changesIdentity: false, normalized: normalized)
            case .invalid(let problems):
                return invalid(problems)
            case .awaitingSetup:
                return invalid(["The \(kind.title) section is empty."])
            }
        case .connect:
            switch ConnectConfigurationLoader.load(normalized, expectedRedirectScheme: expectedRedirectScheme) {
            case .ready(let c):
                var destinations = [
                    "Sign-in — \(c.authorizationEndpoint.host ?? "?")",
                    "Tokens — \(c.tokenEndpoint.host ?? "?")",
                    "App Access — \(c.appAccessEndpoint.host ?? "?")",
                    "Redirect — \(c.redirectURI.absoluteString)",
                    "App identifier — \(c.appIdentifier)",
                ]
                if let signOut = c.signOutEndpoint { destinations.append("Sign-out — \(signOut.host ?? "?")") }
                for link in c.managementLinks { destinations.append("Management link — \(link.title): \(link.url.host ?? "?")") }
                let changes = Self.identityFingerprint(c) != currentConnectFingerprint()
                return ConfigurationImportPreview(kind: kind, environment: c.environment, destinations: destinations,
                                                  problems: [], notes: notes, changesIdentity: changes, normalized: normalized)
            case .invalid(let problems):
                return invalid(problems)
            case .awaitingSetup:
                return invalid(["The \(kind.title) section is empty."])
            }
        }
    }

    /// Applies a valid preview. On any failure the previous configuration stays active.
    @discardableResult
    public func apply(_ preview: ConfigurationImportPreview) throws -> ConfigurationChange {
        guard preview.isValid, let data = preview.normalized else { throw ConfigurationStoreError.invalidPreview }
        let before = currentConnectFingerprint()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = fileURL(preview.kind)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: previousURL(preview.kind))
                try fm.copyItem(at: url, to: previousURL(preview.kind))
            }
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ConfigurationStoreError.writeFailed
        }
        let after = currentConnectFingerprint()
        return ConfigurationChange(kind: preview.kind, identityChanged: preview.kind == .connect && before != after)
    }

    /// Removes the imported configuration; the bundled one (if any) applies again.
    @discardableResult
    public func remove(_ kind: ConfigurationKind) -> ConfigurationChange {
        let before = currentConnectFingerprint()
        try? FileManager.default.removeItem(at: fileURL(kind))
        let after = currentConnectFingerprint()
        return ConfigurationChange(kind: kind, identityChanged: kind == .connect && before != after)
    }

    /// The imported file of `kind`, for "Export configuration" (contains no secrets by construction).
    public func importedData(_ kind: ConfigurationKind) -> Data? {
        try? Data(contentsOf: fileURL(kind))
    }

    // MARK: Helpers

    private func currentConnectFingerprint() -> String? {
        connectState().0.configuration.map(Self.identityFingerprint)
    }

    /// Identity-relevant fields. A change means a different identity setup:
    /// existing sessions and account data must not carry over.
    static func identityFingerprint(_ c: ConnectConfiguration) -> String {
        [c.environment, c.issuer.absoluteString, c.clientID, c.appIdentifier, c.appAccessEndpoint.absoluteString].joined(separator: "|")
    }

    static func section(_ kind: ConfigurationKind, in data: Data) -> (key: String, value: Any)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return section(kind, in: object)
    }

    static func section(_ kind: ConfigurationKind, in object: [String: Any]) -> (key: String, value: Any)? {
        for key in kind.sectionKeys { if let value = object[key] { return (key, value) } }
        return nil
    }

    static func wrap(_ key: String, _ section: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: [key: section], options: [.sortedKeys])) ?? Data()
    }
}
