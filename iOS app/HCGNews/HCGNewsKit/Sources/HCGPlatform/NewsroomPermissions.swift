import Foundation

/// HCG News newsroom roles, as HCG's central access system assigns them. The server
/// function `news_has_feature(_user_id, _feature_key)` is the authority; the keys below
/// are the ones the HCG News website checks.
public enum NewsroomRole: String, CaseIterable, Sendable, Hashable {
    case administrator
    case editorInChief
    case editor
    case journalist
    case contributor

    public var featureKey: String {
        switch self {
        case .administrator: "news.administrator"
        case .editorInChief: "news.editor_in_chief"
        case .editor: "news.editor"
        case .journalist: "news.journalist"
        case .contributor: "news.contributor"
        }
    }

    public var title: String {
        switch self {
        case .administrator: "Administrator"
        case .editorInChief: "Editor-in-Chief"
        case .editor: "Editor"
        case .journalist: "Journalist"
        case .contributor: "Contributor"
        }
    }
}

/// Editorial statuses used by the publication.
public enum EditorialStatus: String, CaseIterable, Sendable, Hashable, Codable {
    case draft
    case inReview = "in_review"
    case approved
    case published
    case archived

    public var title: String {
        switch self {
        case .draft: "Draft"
        case .inReview: "In Review"
        case .approved: "Approved"
        case .published: "Published"
        case .archived: "Archived"
        }
    }
}

/// What the app offers a signed-in person in the newsroom. Derived only from the roles
/// HCG returned in this session, using the same rules as the HCG News website.
///
/// This decides what is *shown*. It is not access control: every read and write is
/// authorised again by the server's row-level security.
public struct NewsroomPermissions: Equatable, Sendable {
    public let roles: Set<NewsroomRole>
    public let checkedAt: Date

    public init(roles: Set<NewsroomRole>, checkedAt: Date) {
        self.roles = roles
        self.checkedAt = checkedAt
    }

    public static let none = NewsroomPermissions(roles: [], checkedAt: .distantPast)

    public var isStaff: Bool { !roles.isEmpty }
    public var isAdministrator: Bool { roles.contains(.administrator) }
    /// Final publication, scheduling, unpublishing and sections: Administrator or Editor-in-Chief.
    public var canPublish: Bool { isAdministrator || roles.contains(.editorInChief) }
    /// Edit anyone's article: Administrator, Editor-in-Chief or Editor.
    public var canEditAny: Bool { canPublish || roles.contains(.editor) }
    public var canViewAudit: Bool { isAdministrator }
    public var canManageSections: Bool { canPublish }
    public var canManageAuthors: Bool { canEditAny }
    public var canUploadMedia: Bool { isStaff }

    /// Highest role first, for display.
    public var orderedRoles: [NewsroomRole] { NewsroomRole.allCases.filter(roles.contains) }

    /// Statuses this person may set.
    public var allowedStatuses: [EditorialStatus] {
        if canPublish { return [.draft, .inReview, .approved, .published, .archived] }
        if roles.contains(.editor) { return [.draft, .inReview, .approved] }
        if isStaff { return [.draft, .inReview] }
        return []
    }

    /// Mirrors the website: editors and above edit everything; others edit only their own
    /// articles while they are drafts or in review.
    public func canEdit(createdBy: String?, status: String, userID: String?) -> Bool {
        if canEditAny { return true }
        guard isStaff, let userID, createdBy == userID else { return false }
        return status == EditorialStatus.draft.rawValue || status == EditorialStatus.inReview.rawValue
    }

    /// Publication (now or scheduled) requires approval first, and the right role.
    public func canPublish(fromStatus status: String) -> Bool {
        canPublish && status == EditorialStatus.approved.rawValue
    }
}

/// Reads the person's newsroom roles from HCG.
public struct NewsroomRoleResolver: Sendable {
    let client: PlatformClient
    let caller: AuthorizedCaller

    public init(client: PlatformClient, caller: AuthorizedCaller) {
        self.client = client
        self.caller = caller
    }

    /// Asks the server about every role. Any failure fails the whole check: a partial
    /// answer is never treated as the person's access.
    public func permissions(userID: String, now: Date = Date()) async throws -> NewsroomPermissions {
        let client = self.client
        let results = try await withThrowingTaskGroup(of: (NewsroomRole, Bool).self) { group in
            for role in NewsroomRole.allCases {
                group.addTask {
                    let granted = try await caller.call { token in
                        let body = try JSONSerialization.data(withJSONObject: ["_user_id": userID, "_feature_key": role.featureKey])
                        let request = try client.restRequest("rpc/news_has_feature", method: "POST", body: body, token: token)
                        let value = try await client.json(request)
                        guard let flag = value as? Bool else { throw PlatformError.contract("news_has_feature did not return true or false") }
                        return flag
                    }
                    return (role, granted)
                }
            }
            var granted: Set<NewsroomRole> = []
            for try await (role, value) in group where value { granted.insert(role) }
            return granted
        }
        return NewsroomPermissions(roles: results, checkedAt: now)
    }
}
