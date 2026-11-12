import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import NewsCore

// Remote newsroom (editorial write) client.
//
// STATUS: the endpoints below are a PROPOSED contract
// (docs/NEWSROOM-API-PROPOSAL.md). The publication currently has no such API:
// its own editor uses internal server functions that are not a supported
// interface. Until a configuration names `content.newsroomAPIBaseURL`, the app
// uses `UnavailableNewsroomService` and every remote action explains why it is
// unavailable. Local drafts work regardless.

public enum NewsroomAction: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Create or update the server copy of a draft.
    case saveDraft = "save_draft"
    case submitForReview = "submit"
    case approve
    case schedule
    case publish
    case correct
    case unpublish
    case uploadMedia = "upload_media"
    case viewQueue = "view_queue"
    case viewAudit = "view_audit"
    case manageSections = "manage_sections"
    case manageAuthors = "manage_authors"
    case manageMedia = "manage_media"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .saveDraft: "Save to newsroom"
        case .submitForReview: "Submit for review"
        case .approve: "Approve"
        case .schedule: "Schedule"
        case .publish: "Publish"
        case .correct: "Issue correction"
        case .unpublish: "Unpublish"
        case .uploadMedia: "Upload media"
        case .viewQueue: "Editorial queue"
        case .viewAudit: "Audit history"
        case .manageSections: "Manage sections"
        case .manageAuthors: "Manage authors"
        case .manageMedia: "Manage media"
        }
    }

    /// Actions that change or remove published content: they need a review
    /// screen and an explicit confirmation.
    public var isDestructive: Bool { self == .unpublish || self == .correct || self == .publish }
}

/// What the newsroom service says it implements, and what it authorises for this account.
/// Both come from the server; the app adds no roles of its own.
public struct NewsroomCapabilities: Equatable, Sendable {
    public let contractVersion: String
    public let supported: Set<NewsroomAction>
    public let allowed: Set<NewsroomAction>
    public let authors: [VerifiedAuthor]
    public let sections: [NewsSection]

    public init(contractVersion: String, supported: Set<NewsroomAction>, allowed: Set<NewsroomAction>,
                authors: [VerifiedAuthor] = [], sections: [NewsSection] = []) {
        self.contractVersion = contractVersion
        self.supported = supported
        self.allowed = allowed.intersection(supported)
        self.authors = authors
        self.sections = sections
    }
}

/// Server-side summary of a newsroom draft or article.
public struct ServerDraftSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let headline: String
    public let status: String
    public let revision: String
    public let updatedAt: Date?
    public let updatedBy: String?
    public let scheduledFor: Date?
}

public struct AuditEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let at: Date
    public let actor: String
    public let action: String
    public let articleID: String?
    public let detail: String?
}

public enum NewsroomError: Error, Equatable, Sendable {
    case notConfigured
    case notSignedIn
    case unsupported(NewsroomAction)
    /// The server refused (403). Its message, if any.
    case denied(String?)
    /// The server holds a newer revision. Nothing was overwritten.
    case conflict(server: ServerDraftSummary)
    case offline
    case validation([String])
    case server(Int)
    case contract(String)
}

public struct ServerDraftContent: Equatable, Sendable {
    public let summary: ServerDraftSummary
    public let draft: Draft
}

public protocol NewsroomService: Sendable {
    func capabilities() async throws -> NewsroomCapabilities
    func queue() async throws -> [ServerDraftSummary]
    func fetchDraft(serverID: String) async throws -> ServerDraftContent
    /// Creates (no link) or updates (with link) the server draft. Updates send the
    /// base revision; a newer server revision yields `.conflict` and changes nothing.
    func saveDraft(_ draft: Draft, mediaRemoteIDs: [UUID: String]) async throws -> ServerDraftSummary
    func perform(_ action: NewsroomAction, serverID: String, baseRevision: String,
                 scheduleAt: Date?, note: String?) async throws -> ServerDraftSummary
    func uploadMedia(data: Data, filename: String, mimeType: String) async throws -> String
    func audit(serverID: String?) async throws -> [AuditEntry]
}

public struct UnavailableNewsroomService: NewsroomService {
    public init() {}
    public func capabilities() async throws -> NewsroomCapabilities { throw NewsroomError.notConfigured }
    public func queue() async throws -> [ServerDraftSummary] { throw NewsroomError.notConfigured }
    public func fetchDraft(serverID: String) async throws -> ServerDraftContent { throw NewsroomError.notConfigured }
    public func saveDraft(_ draft: Draft, mediaRemoteIDs: [UUID: String]) async throws -> ServerDraftSummary { throw NewsroomError.notConfigured }
    public func perform(_ action: NewsroomAction, serverID: String, baseRevision: String, scheduleAt: Date?, note: String?) async throws -> ServerDraftSummary { throw NewsroomError.notConfigured }
    public func uploadMedia(data: Data, filename: String, mimeType: String) async throws -> String { throw NewsroomError.notConfigured }
    public func audit(serverID: String?) async throws -> [AuditEntry] { throw NewsroomError.notConfigured }
}

// MARK: - Availability

public enum ActionAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    public var isAvailable: Bool { self == .available }
    public var reason: String? { if case .unavailable(let r) = self { return r }; return nil }
}

/// Decides whether a remote action can be offered. Every input comes from HCG or the
/// newsroom service; the app never grants anything itself, and the server checks again.
public enum NewsroomGate {
    public static func availability(_ action: NewsroomAction,
                                    serviceConfigured: Bool,
                                    signedIn: Bool,
                                    centralAccessGranted: Bool,
                                    capabilities: NewsroomCapabilities?) -> ActionAvailability {
        guard serviceConfigured else {
            return .unavailable("No newsroom service is configured for HCG News. Your local drafts are safe; export them to share with the newsroom.")
        }
        guard signedIn else { return .unavailable("Sign in with HCG Connect to use newsroom actions.") }
        guard centralAccessGranted else {
            return .unavailable("HCG has not granted newsroom access to this account in this session.")
        }
        guard let capabilities else { return .unavailable("Newsroom capabilities haven't been loaded. Check the connection.") }
        guard capabilities.supported.contains(action) else {
            return .unavailable("The newsroom service doesn't support “\(action.title)” yet.")
        }
        guard capabilities.allowed.contains(action) else {
            return .unavailable("The newsroom service hasn't authorised “\(action.title)” for your account.")
        }
        return .available
    }
}

// MARK: - Client for the proposed contract

public actor NewsroomAPIClient: NewsroomService {
    public typealias TokenProvider = @Sendable () async -> String?

    private let baseURL: URL
    private let transport: HTTPTransport
    private let token: TokenProvider
    private let userAgent: String
    private let environment: String

    public init(baseURL: URL, environment: String, transport: HTTPTransport, userAgent: String, token: @escaping TokenProvider) {
        self.baseURL = baseURL
        self.environment = environment
        self.transport = transport
        self.userAgent = userAgent
        self.token = token
    }

    struct CapabilitiesResponse: Decodable {
        let contractVersion: String
        let supportedActions: [String]
        let allowedActions: [String]
        let authors: [VerifiedAuthor]?
        let sections: [NewsSection]?
    }

    public func capabilities() async throws -> NewsroomCapabilities {
        let r: CapabilitiesResponse = try await request("capabilities")
        guard r.contractVersion == "1" else { throw NewsroomError.contract("Unsupported newsroom contract version \(r.contractVersion).") }
        return NewsroomCapabilities(
            contractVersion: r.contractVersion,
            supported: Set(r.supportedActions.compactMap(NewsroomAction.init(rawValue:))),
            allowed: Set(r.allowedActions.compactMap(NewsroomAction.init(rawValue:))),
            authors: r.authors ?? [], sections: r.sections ?? [])
    }

    public func queue() async throws -> [ServerDraftSummary] {
        struct R: Decodable { let items: [ServerDraftSummary] }
        let r: R = try await request("queue")
        return r.items
    }

    public func fetchDraft(serverID: String) async throws -> ServerDraftContent {
        struct R: Decodable { let summary: ServerDraftSummary; let draft: Draft }
        let r: R = try await request("drafts/" + Self.path(serverID))
        return ServerDraftContent(summary: r.summary, draft: r.draft)
    }

    public func saveDraft(_ draft: Draft, mediaRemoteIDs: [UUID: String]) async throws -> ServerDraftSummary {
        struct Body: Encodable {
            let baseRevision: String?
            let draft: Draft
            let media: [String: String]
        }
        var payload = draft
        payload.serverLink = nil
        let body = Body(baseRevision: draft.serverLink?.serverRevision, draft: payload,
                        media: Dictionary(uniqueKeysWithValues: mediaRemoteIDs.map { ($0.key.uuidString, $0.value) }))
        if let link = draft.serverLink {
            return try await request("drafts/" + Self.path(link.serverDraftID), method: "PUT", body: body)
        }
        return try await request("drafts", method: "POST", body: body)
    }

    public func perform(_ action: NewsroomAction, serverID: String, baseRevision: String,
                        scheduleAt: Date?, note: String?) async throws -> ServerDraftSummary {
        struct Body: Encodable { let baseRevision: String; let scheduleAt: Date?; let note: String? }
        return try await request("drafts/\(Self.path(serverID))/actions/\(action.rawValue)", method: "POST",
                                 body: Body(baseRevision: baseRevision, scheduleAt: scheduleAt, note: note))
    }

    public func uploadMedia(data: Data, filename: String, mimeType: String) async throws -> String {
        struct R: Decodable { let id: String }
        let r: R = try await request("media?filename=" + Self.query(filename), method: "POST", rawBody: data, contentType: mimeType)
        return r.id
    }

    public func audit(serverID: String?) async throws -> [AuditEntry] {
        struct R: Decodable { let items: [AuditEntry] }
        let r: R = try await request(serverID.map { "audit?draft=" + Self.query($0) } ?? "audit")
        return r.items
    }

    // MARK: HTTP

    struct ErrorBody: Decodable { let error: String?; let message: String?; let problems: [String]?; let current: ServerDraftSummary? }

    static func path(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func query(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET") async throws -> T {
        try await send(path, method: method, body: nil, contentType: nil)
    }

    private func request<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T {
        let data = try HCGJSON.makeEncoder().encode(body)
        return try await send(path, method: method, body: data, contentType: "application/json")
    }

    private func request<T: Decodable>(_ path: String, method: String, rawBody: Data, contentType: String) async throws -> T {
        try await send(path, method: method, body: rawBody, contentType: contentType)
    }

    private func send<T: Decodable>(_ path: String, method: String, body: Data?, contentType: String?) async throws -> T {
        guard let bearer = await token() else { throw NewsroomError.notSignedIn }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL, HCGHostPolicy.isTrustedHCGURL(url) else {
            throw NewsroomError.contract("Refusing to call a non-HCG host.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw NewsroomError.offline
        }
        switch response.statusCode {
        case 200..<300:
            do { return try HCGJSON.makeDecoder().decode(T.self, from: data) } catch {
                throw NewsroomError.contract("The newsroom response did not match the agreed contract.")
            }
        case 401: throw NewsroomError.notSignedIn
        case 403: throw NewsroomError.denied((try? JSONDecoder().decode(ErrorBody.self, from: data))?.message)
        case 404, 501: throw NewsroomError.notConfigured
        case 409:
            if let current = (try? HCGJSON.makeDecoder().decode(ErrorBody.self, from: data))?.current {
                throw NewsroomError.conflict(server: current)
            }
            throw NewsroomError.contract("The server reported a conflict without its current revision.")
        case 422: throw NewsroomError.validation((try? JSONDecoder().decode(ErrorBody.self, from: data))?.problems ?? [])
        default: throw NewsroomError.server(response.statusCode)
        }
    }
}
