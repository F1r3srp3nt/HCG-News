import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import NewsCore

/// The HCG News newsroom, through the same tables, server function and storage bucket
/// the HCG News website's newsroom uses, with the signed-in person's own token. The
/// server's row-level security decides every read and write; this client never
/// widens what a person can do.
public struct NewsroomRepository: Sendable {
    public static let mediaBucket = "hcg-news-media"
    /// The website signs media URLs for ten years.
    public static let signedURLLifetime = 315_360_000
    public static let imageTypes = ["image/jpeg", "image/png", "image/webp", "image/gif", "image/avif"]
    public static let videoTypes = ["video/mp4", "video/webm", "video/quicktime"]
    public static let maxImageBytes = 20 * 1024 * 1024
    public static let maxVideoBytes = 500 * 1024 * 1024

    static let listColumns = "id,title,slug,status,content_type,published_at,updated_at,is_featured,is_breaking,is_demo,created_by,category:news_categories(name,slug),author:news_authors(name)"

    let client: PlatformClient
    let caller: AuthorizedCaller
    let now: @Sendable () -> Date

    public init(client: PlatformClient, caller: AuthorizedCaller, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.caller = caller
        self.now = now
    }

    // MARK: Articles

    public func articles(status: EditorialStatus? = nil) async throws -> [NewsroomArticleSummary] {
        let client = self.client
        var query = [URLQueryItem(name: "select", value: Self.listColumns),
                     URLQueryItem(name: "order", value: "updated_at.desc"),
                     URLQueryItem(name: "limit", value: "300")]
        if let status { query.append(URLQueryItem(name: "status", value: "eq.\(status.rawValue)")) }
        let finalQuery = query
        let rows = try await caller.call { token in
            try await client.rows(client.restRequest("news_articles", query: finalQuery, token: token))
        }
        return rows.map(Row.init).compactMap(Self.summary)
    }

    public func article(id: String) async throws -> NewsroomArticle {
        let client = self.client
        let rows = try await caller.call { token in
            try await client.rows(client.restRequest("news_articles", query: [
                URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "id", value: "eq.\(id)"),
            ], token: token))
        }
        guard let row = rows.first, let article = Self.article(Row(row)) else { throw PlatformError.notFound }
        return article
    }

    /// Creates an empty draft owned by the person, as the website does.
    public func createDraft(userID: String) async throws -> NewsroomArticle {
        let client = self.client
        let body = try JSONSerialization.data(withJSONObject: [
            "title": "Untitled article", "slug": "draft-\(UUID().uuidString.lowercased())",
            "status": EditorialStatus.draft.rawValue, "created_by": userID,
        ])
        let rows = try await caller.call { token in
            try await client.rows(client.restRequest("news_articles", query: [URLQueryItem(name: "select", value: "*")],
                                                     method: "POST", body: body, token: token, prefer: "return=representation"))
        }
        guard let row = rows.first, let article = Self.article(Row(row)) else { throw PlatformError.contract("created row missing") }
        return article
    }

    /// Saves changed fields (and optionally a status change) only if nobody else changed
    /// the article since `base` was loaded. On a status change, a version snapshot is
    /// recorded as the website does.
    public func save(_ fields: NewsroomArticleFields, over base: NewsroomArticle,
                     status: EditorialStatus? = nil, publishedAt: Date? = nil,
                     userID: String) async throws(NewsroomSaveError) -> (article: NewsroomArticle, versionRecorded: Bool) {
        var changes = fields.changes(from: base.fields)
        if let status, status.rawValue != base.status { changes["status"] = status.rawValue }
        if let publishedAt { changes["published_at"] = HCGJSON.formatDate(publishedAt) }
        if changes.isEmpty { return (base, false) }
        changes["updated_at"] = HCGJSON.formatDate(now())

        let client = self.client
        let rows: [[String: Any]]
        do {
            let body = try JSONSerialization.data(withJSONObject: changes, options: [.sortedKeys])
            let query = [URLQueryItem(name: "id", value: "eq.\(base.id)"),
                         URLQueryItem(name: "updated_at", value: "eq.\(base.revision)"),
                         URLQueryItem(name: "select", value: "*")]
            rows = try await caller.call { token in
                try await client.rows(client.restRequest("news_articles", query: query, method: "PATCH", body: body,
                                                         token: token, prefer: "return=representation"))
            }
        } catch let error as PlatformError {
            throw .platform(error)
        } catch {
            throw .platform(.other("\(error)"))
        }

        guard let row = rows.first, let saved = Self.article(Row(row)) else {
            // Nothing matched: either someone changed it, or the server refused the change.
            let current: NewsroomArticle
            do { current = try await article(id: base.id) }
            catch let error as PlatformError { throw .platform(error == .notFound ? .notFound : error) }
            catch { throw .platform(.other("\(error)")) }
            if current.revision != base.revision { throw .conflict(server: current) }
            throw .platform(.forbidden("the server didn't apply the change"))
        }

        var recorded = false
        if changes["status"] != nil {
            recorded = (try? await recordVersion(of: saved, userID: userID)) != nil
        }
        return (saved, recorded)
    }

    func recordVersion(of article: NewsroomArticle, userID: String) async throws {
        let client = self.client
        var object: [String: Any] = ["article_id": article.id, "title": article.fields.title,
                                     "body": article.fields.body, "status": article.status, "created_by": userID]
        object["subtitle"] = article.fields.subtitle.isEmpty ? NSNull() : article.fields.subtitle
        let body = try JSONSerialization.data(withJSONObject: object)
        _ = try await caller.call { token in
            try await client.send(client.restRequest("news_article_versions", method: "POST", body: body, token: token,
                                                     prefer: "return=minimal"))
        }
    }

    public func versions(articleID: String) async throws -> [NewsroomVersion] {
        let client = self.client
        let rows = try await caller.call { token in
            try await client.rows(client.restRequest("news_article_versions", query: [
                URLQueryItem(name: "select", value: "id,title,subtitle,body,status,created_at,created_by"),
                URLQueryItem(name: "article_id", value: "eq.\(articleID)"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "100"),
            ], token: token))
        }
        return rows.map(Row.init).compactMap { r in
            guard let id = r.string("id") else { return nil }
            return NewsroomVersion(id: id, title: r.string("title"), subtitle: r.string("subtitle"), body: r.string("body"),
                                   status: r.string("status"), createdAt: r.date("created_at"), createdBy: r.string("created_by"))
        }
    }

    // MARK: Audit, sections, authors

    public func audit() async throws -> [NewsroomAuditEntry] {
        let client = self.client
        let rows = try await caller.call { token in
            try await client.rows(client.restRequest("news_audit", query: [
                URLQueryItem(name: "select", value: "id,created_at,actor_id,action,entity,summary"),
                URLQueryItem(name: "order", value: "created_at.desc"), URLQueryItem(name: "limit", value: "300"),
            ], token: token))
        }
        return rows.map(Row.init).compactMap { r in
            guard let id = r.string("id") else { return nil }
            return NewsroomAuditEntry(id: id, createdAt: r.date("created_at"), actorID: r.string("actor_id"),
                                      action: r.string("action") ?? "?", entity: r.string("entity"), summary: r.string("summary"))
        }
    }

    public func categories() async throws -> [NewsroomCategory] {
        let client = self.client
        let rows = try await caller.call { token in
            try await client.rows(client.restRequest("news_categories", query: [
                URLQueryItem(name: "select", value: "id,name,slug,description,sort_order,is_visible"),
                URLQueryItem(name: "order", value: "sort_order.asc.nullslast,name.asc"),
            ], token: token))
        }
        return rows.map(Row.init).compactMap(Self.category)
    }

    public func createCategory(name: String, sortOrder: Int) async throws -> NewsroomCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = NewsroomArticleFields.slugify(trimmed)
        guard !trimmed.isEmpty, !slug.isEmpty else { throw PlatformError.other("Enter a section name.") }
        let client = self.client
        let body = try JSONSerialization.data(withJSONObject: ["name": trimmed, "slug": slug, "sort_order": sortOrder])
        let rows = try await caller.call { token in
            try await client.rows(client.restRequest("news_categories", query: [URLQueryItem(name: "select", value: "*")],
                                                     method: "POST", body: body, token: token, prefer: "return=representation"))
        }
        guard let row = rows.first, let category = Self.category(Row(row)) else { throw PlatformError.forbidden(nil) }
        return category
    }

    /// Renames, re-slugs, re-describes or hides a section. Returns the updated row.
    public func updateCategory(id: String, changes: [String: Any]) async throws -> NewsroomCategory {
        let client = self.client
        let body = try JSONSerialization.data(withJSONObject: changes)
        let rows = try await caller.call { token in
            try await client.rows(client.restRequest("news_categories", query: [
                URLQueryItem(name: "id", value: "eq.\(id)"), URLQueryItem(name: "select", value: "*"),
            ], method: "PATCH", body: body, token: token, prefer: "return=representation"))
        }
        guard let row = rows.first, let category = Self.category(Row(row)) else { throw PlatformError.forbidden(nil) }
        return category
    }

    public func authors() async throws -> [NewsroomAuthor] {
        let client = self.client
        let rows = try await caller.call { token in
            try await client.rows(client.restRequest("news_authors", query: [
                URLQueryItem(name: "select", value: "id,name,slug,title,user_id"), URLQueryItem(name: "order", value: "name.asc"),
            ], token: token))
        }
        return rows.map(Row.init).compactMap { r in
            guard let id = r.string("id"), let name = r.nonEmpty("name") else { return nil }
            return NewsroomAuthor(id: id, name: name, slug: r.string("slug"), title: r.nonEmpty("title"), userID: r.string("user_id"))
        }
    }

    // MARK: Media

    public func media() async throws -> [NewsroomMedia] {
        let client = self.client
        let rows = try await caller.call { token in
            try await client.rows(client.restRequest("news_media", query: [
                URLQueryItem(name: "select", value: "id,storage_path,url,kind,mime_type,size_bytes,uploaded_by,caption,alt_text,credit,created_at"),
                URLQueryItem(name: "order", value: "created_at.desc"), URLQueryItem(name: "limit", value: "300"),
            ], token: token))
        }
        return rows.map(Row.init).compactMap(Self.media)
    }

    /// Validates a file the way the website does. Nil when acceptable.
    public static func uploadProblem(mimeType: String, byteCount: Int) -> String? {
        let isImage = imageTypes.contains(mimeType), isVideo = videoTypes.contains(mimeType)
        guard isImage || isVideo else { return "Use JPEG, PNG, WebP, GIF, AVIF, MP4, WebM or MOV." }
        if byteCount == 0 { return "The file is empty." }
        let limit = isVideo ? maxVideoBytes : maxImageBytes
        if byteCount > limit { return "File too large (max \(limit / 1024 / 1024) MB for \(isVideo ? "videos" : "images"))." }
        return nil
    }

    /// The website's storage layout: `articles/<id>/<kind>s/<uuid>.<ext>` or `library/<kind>s/…`.
    public static func storagePath(mimeType: String, fileExtension: String, articleID: String?, id: UUID = UUID()) -> String {
        let kind = videoTypes.contains(mimeType) ? "video" : "image"
        let ext = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        let folder = articleID.map { "articles/\($0)" } ?? "library"
        return "\(folder)/\(kind)s/\(id.uuidString.lowercased()).\(ext.isEmpty ? "bin" : ext)"
    }

    /// Uploads a file to the newsroom's media bucket, signs it as the website does and
    /// records it in the media library with its caption, alt text and credit. If the
    /// library record can't be written, the uploaded file is removed again.
    public func upload(data: Data, mimeType: String, fileExtension: String, articleID: String?, userID: String,
                       caption: String?, altText: String?, credit: String?) async throws -> NewsroomMedia {
        if let problem = Self.uploadProblem(mimeType: mimeType, byteCount: data.count) { throw PlatformError.other(problem) }
        let client = self.client
        let path = Self.storagePath(mimeType: mimeType, fileExtension: fileExtension, articleID: articleID)
        let objectURL = client.configuration.storageURL.appendingPathComponent("object/\(Self.mediaBucket)/\(path)")

        _ = try await caller.call { token in
            var request = client.baseRequest(objectURL, method: "POST", token: token)
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            request.setValue("false", forHTTPHeaderField: "x-upsert")
            request.httpBody = data
            return try await client.send(request)
        }

        do {
            let signURL = client.configuration.storageURL.appendingPathComponent("object/sign/\(Self.mediaBucket)/\(path)")
            let signedPath: String = try await caller.call { token in
                var request = client.baseRequest(signURL, method: "POST", token: token)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": Self.signedURLLifetime])
                guard let object = try await client.json(request) as? [String: Any],
                      let signed = (object["signedURL"] as? String) ?? (object["signedUrl"] as? String)
                else { throw PlatformError.contract("no signed URL") }
                return signed
            }
            guard let signedURL = URL(string: client.configuration.storageURL.absoluteString + (signedPath.hasPrefix("/") ? "" : "/") + signedPath)
            else { throw PlatformError.contract("invalid signed URL") }

            var row: [String: Any] = [
                "storage_path": path, "url": signedURL.absoluteString,
                "kind": Self.videoTypes.contains(mimeType) ? "video" : "image",
                "mime_type": mimeType, "size_bytes": data.count, "uploaded_by": userID,
            ]
            func optional(_ key: String, _ value: String?) {
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                row[key] = trimmed.isEmpty ? NSNull() : trimmed
            }
            optional("caption", caption); optional("alt_text", altText); optional("credit", credit)
            let body = try JSONSerialization.data(withJSONObject: row)
            let rows = try await caller.call { token in
                try await client.rows(client.restRequest("news_media", query: [URLQueryItem(name: "select", value: "*")],
                                                         method: "POST", body: body, token: token, prefer: "return=representation"))
            }
            guard let first = rows.first, let media = Self.media(Row(first)) else { throw PlatformError.contract("media row missing") }
            return media
        } catch {
            _ = try? await caller.call { token in
                var request = client.baseRequest(client.configuration.storageURL.appendingPathComponent("object/\(Self.mediaBucket)"),
                                                 method: "DELETE", token: token)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["prefixes": [path]])
                return try await client.send(request)
            }
            throw error
        }
    }

    public func updateMedia(id: String, caption: String, altText: String, credit: String) async throws -> NewsroomMedia {
        let client = self.client
        func value(_ s: String) -> Any { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? NSNull() : t }
        let body = try JSONSerialization.data(withJSONObject: ["caption": value(caption), "alt_text": value(altText), "credit": value(credit)])
        let rows = try await caller.call { token in
            try await client.rows(client.restRequest("news_media", query: [
                URLQueryItem(name: "id", value: "eq.\(id)"), URLQueryItem(name: "select", value: "*"),
            ], method: "PATCH", body: body, token: token, prefer: "return=representation"))
        }
        guard let row = rows.first, let media = Self.media(Row(row)) else { throw PlatformError.forbidden(nil) }
        return media
    }

    // MARK: Mapping

    static func summary(_ r: Row) -> NewsroomArticleSummary? {
        guard let id = r.string("id") else { return nil }
        return NewsroomArticleSummary(
            id: id, title: r.nonEmpty("title") ?? "Untitled article", slug: r.string("slug"),
            status: r.string("status") ?? "unknown", contentType: r.string("content_type"),
            publishedAt: r.date("published_at"), updatedAt: r.date("updated_at"),
            isFeatured: r.bool("is_featured"), isBreaking: r.bool("is_breaking"), isDemo: r.bool("is_demo"),
            sectionName: r.embedded("category")?.nonEmpty("name"), authorName: r.embedded("author")?.nonEmpty("name"),
            createdBy: r.string("created_by"))
    }

    static func article(_ r: Row) -> NewsroomArticle? {
        guard let id = r.string("id"), let revision = r.string("updated_at") else { return nil }
        let fields = NewsroomArticleFields(
            title: r.string("title") ?? "", subtitle: r.string("subtitle") ?? "", slug: r.string("slug") ?? "",
            excerpt: r.string("excerpt") ?? "", body: r.string("body") ?? "", contentType: r.string("content_type") ?? "news",
            categoryID: r.string("category_id"), authorID: r.string("author_id"),
            featuredImageURL: r.string("featured_image_url") ?? "", featuredImageAlt: r.string("featured_image_alt") ?? "",
            featuredImageCaption: r.string("featured_image_caption") ?? "", featuredImageCredit: r.string("featured_image_credit") ?? "",
            isFeatured: r.bool("is_featured"), isBreaking: r.bool("is_breaking"),
            seoTitle: r.string("seo_title") ?? "", seoDescription: r.string("seo_description") ?? "",
            tags: r.strings("tags"), sources: r.string("sources") ?? "", correctionNotes: r.string("correction_notes") ?? "")
        return NewsroomArticle(id: id, createdBy: r.string("created_by"), createdAt: r.date("created_at"), revision: revision,
                               updatedAt: r.date("updated_at"), status: r.string("status") ?? "unknown",
                               publishedAt: r.date("published_at"), isDemo: r.bool("is_demo"), viewCount: r.int("view_count"),
                               fields: fields)
    }

    static func category(_ r: Row) -> NewsroomCategory? {
        guard let id = r.string("id"), let name = r.nonEmpty("name"), let slug = r.nonEmpty("slug") else { return nil }
        return NewsroomCategory(id: id, name: name, slug: slug, description: r.nonEmpty("description"),
                                sortOrder: r.int("sort_order"), isVisible: (r.raw["is_visible"] as? Bool) ?? true)
    }

    static func media(_ r: Row) -> NewsroomMedia? {
        guard let id = r.string("id"), let path = r.string("storage_path") else { return nil }
        return NewsroomMedia(id: id, url: r.url("url"), storagePath: path, kind: r.string("kind") ?? "image",
                             mimeType: r.string("mime_type"), sizeBytes: r.int("size_bytes"), uploadedBy: r.string("uploaded_by"),
                             caption: r.nonEmpty("caption"), altText: r.nonEmpty("alt_text"), credit: r.nonEmpty("credit"),
                             createdAt: r.date("created_at"))
    }
}
