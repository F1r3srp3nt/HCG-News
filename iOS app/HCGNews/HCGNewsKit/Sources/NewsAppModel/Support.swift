import Foundation
import HCGTransport
import NewsCore
import HCGConnect

// MARK: - Local troubleshooting log

/// One entry in the ON-DEVICE troubleshooting history. This is not the server's
/// audit history: it records only what this app did on this device, and never
/// contains tokens, codes, secrets or article text.
public struct LocalEvent: Codable, Equatable, Sendable, Identifiable {
    public enum Category: String, Codable, Sendable { case configuration, connection, account, download, newsroom, app }
    public let id: UUID
    public let at: Date
    public let category: Category
    public let message: String

    public init(at: Date, category: Category, message: String) {
        self.id = UUID()
        self.at = at
        self.category = category
        self.message = message
    }
}

public actor LocalEventLog {
    private let fileURL: URL?
    private let limit: Int
    private var events: [LocalEvent] = []
    private var loaded = false

    public init(fileURL: URL?, limit: Int = 300) {
        self.fileURL = fileURL
        self.limit = limit
    }

    public func record(_ category: LocalEvent.Category, _ message: String, at date: Date = Date()) {
        loadIfNeeded()
        events.insert(LocalEvent(at: date, category: category, message: Self.scrub(message)), at: 0)
        if events.count > limit { events.removeLast(events.count - limit) }
        persist()
    }

    public func all() -> [LocalEvent] {
        loadIfNeeded()
        return events
    }

    public func clear() {
        events = []
        loaded = true
        persist()
    }

    /// Defensive redaction of anything that looks like a bearer token or JWT.
    static func scrub(_ message: String) -> String {
        var text = message
        for pattern in [#"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*"#, #"(?i)bearer\s+[A-Za-z0-9._\-]+"#] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[redacted]")
            }
        }
        return text
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? HCGJSON.makeDecoder().decode([LocalEvent].self, from: data) else { return }
        events = decoded
    }

    private func persist() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? HCGJSON.makeEncoder().encode(events) { try? data.write(to: fileURL, options: [.atomic]) }
    }
}

// MARK: - Diagnostics export

/// A plain-text report for support. Contains no tokens, keys, codes or personal data:
/// hosts, environments, states and the local event history only.
public enum DiagnosticsReport {
    public static func make(appVersion: String,
                            publication: (NewsConfigurationState, ConfigurationSource),
                            connect: (ConnectConfigurationState, ConfigurationSource),
                            publicationCheck: String,
                            connectCheck: String,
                            offlineCount: Int, offlineBytes: Int64,
                            events: [LocalEvent]) -> String {
        var lines: [String] = []
        lines.append("HCG News diagnostics")
        lines.append("App version: \(appVersion)")
        lines.append("Generated: \(HCGJSON.formatDate(Date()))")
        lines.append("")
        lines.append("Publication configuration: \(sourceLabel(publication.1))")
        switch publication.0 {
        case .ready(let c):
            lines.append("  environment: \(c.environment), contract v\(c.contractVersion)")
            lines.append("  content API host: \(c.apiBaseURL.host ?? "?")")
            lines.append("  newsroom API host: \(c.newsroomAPIBaseURL?.host ?? "none")")
        case .awaitingSetup: lines.append("  none installed")
        case .invalid(let problems): lines.append("  INVALID: " + problems.joined(separator: " | "))
        }
        lines.append("  connection check: \(publicationCheck)")
        lines.append("")
        lines.append("HCG Connect configuration: \(sourceLabel(connect.1))")
        switch connect.0 {
        case .ready(let c):
            lines.append("  environment: \(c.environment)")
            lines.append("  issuer host: \(c.issuer.host ?? "?"), App Access host: \(c.appAccessEndpoint.host ?? "?")")
            lines.append("  client id: [redacted], public key: \(c.providerPublicKey == nil ? "none" : "[redacted]")")
        case .awaitingSetup: lines.append("  none installed")
        case .invalid(let problems): lines.append("  INVALID: " + problems.joined(separator: " | "))
        }
        lines.append("  connection check: \(connectCheck)")
        lines.append("")
        lines.append("Offline downloads: \(offlineCount) (\(ByteCountFormatter.string(fromByteCount: offlineBytes, countStyle: .file)))")
        lines.append("")
        lines.append("On-device event history (not server audit history):")
        for event in events.prefix(100) {
            lines.append("  \(HCGJSON.formatDate(event.at)) [\(event.category.rawValue)] \(event.message)")
        }
        return lines.joined(separator: "\n")
    }

    static func sourceLabel(_ source: ConfigurationSource) -> String {
        switch source {
        case .imported(let date): return "imported \(HCGJSON.formatDate(date))"
        case .bundled: return "built into the app"
        case .none: return "none"
        }
    }
}

// MARK: - Notification preferences (local only)

/// Topics a reader would like to be notified about. Stored on this device only.
/// Push notifications are NOT active: HCG News has no notification service and
/// the app is not registered with Apple Push Notification service. The preferences
/// are kept so they can be honoured once a service exists.
public struct NotificationPreferences: Codable, Equatable, Sendable {
    public var breakingNews: Bool
    /// Breaking categories the publication flags (label values), e.g. "Breaking", "Developing".
    public var breakingCategories: Set<String>
    /// Section slugs.
    public var sections: Set<String>
    public var hcgAnnouncements: Bool

    public init(breakingNews: Bool = false, breakingCategories: Set<String> = [], sections: Set<String> = [], hcgAnnouncements: Bool = false) {
        self.breakingNews = breakingNews
        self.breakingCategories = breakingCategories
        self.sections = sections
        self.hcgAnnouncements = hcgAnnouncements
    }

    public static let storageKey = "notificationPreferences.v1"

    public static func load(from defaults: UserDefaults) -> NotificationPreferences {
        guard let data = defaults.data(forKey: storageKey),
              let prefs = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else { return NotificationPreferences() }
        return prefs
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

public enum ServiceAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
}

/// Honest availability of secondary features. Nothing here is simulated.
public enum SecondaryFeatures {
    public static let pushNotifications = ServiceAvailability.unavailable(
        "Notifications aren't active yet. HCG News has no notification service, and this app is not registered for push notifications. Your choices are saved on this device for when the service exists.")
    public static let savedArticleSync = ServiceAvailability.unavailable(
        "Saved articles stay on this device. Sync between devices needs an HCG service that doesn't exist yet.")
    public static let readAloud = ServiceAvailability.available
}
