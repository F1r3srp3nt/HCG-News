import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import HCGTestSupport
@testable import HCGPlatform

final class NewsroomRepositoryTests: XCTestCase {
    let articleID = testArticleID

    func repository(_ transport: FakeTransport) async throws -> NewsroomRepository {
        let client = PlatformClient(configuration: testPlatform, transport: transport, userAgent: "t")
        let account = HCGAccountSession(client: client, store: MemorySessionStore(), now: { fixedNow })
        _ = try await account.signIn(email: "a@b.c", password: "p")
        return NewsroomRepository(client: client, caller: AuthorizedCaller(account: account), now: { fixedNow })
    }

    func handler(_ rest: @escaping @Sendable (URLRequest) -> (Int, Data)) -> FakeTransport {
        FakeTransport { request in request.path == "/auth/v1/token" ? (200, tokenResponse()) : rest(request) }
    }

    func testSaveSendsOnlyChangedFieldsGuardedByTheLoadedRevision() async throws {
        let transport = handler { _ in (200, json([fullRow(revision: "2026-11-10T10:00:00+00:00", title: "Edited test headline")])) }
        let repo = try await repository(transport)
        let base = try XCTUnwrap(NewsroomRepository.article(Row(fullRow())))
        var fields = base.fields
        fields.title = "Edited test headline"
        fields.subtitle = "   "
        let result = try await repo.save(fields, over: base, userID: "user-1")
        XCTAssertEqual(result.article.fields.title, "Edited test headline")
        XCTAssertFalse(result.versionRecorded)
        let patch = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(patch.httpMethod, "PATCH")
        XCTAssertEqual(patch.query["id"], "eq.\(articleID)")
        XCTAssertEqual(patch.query["updated_at"], "eq.2026-11-10T09:00:00.123456+00:00")
        XCTAssertEqual(patch.bearer, "access-1")
        let body = patch.bodyObject
        XCTAssertEqual(Set(body.keys), ["title", "updated_at"], "unchanged fields (including the body) are never sent")
        XCTAssertEqual(patch.value(forHTTPHeaderField: "Prefer"), "return=representation")
    }

    func testConcurrentEditIsAConflictAndNothingIsOverwritten() async throws {
        let transport = handler { request in
            if request.httpMethod == "PATCH" { return (200, json([])) }
            return (200, json([fullRow(revision: "2026-11-10T11:11:11+00:00", title: "Changed elsewhere")]))
        }
        let repo = try await repository(transport)
        let base = try XCTUnwrap(NewsroomRepository.article(Row(fullRow())))
        var fields = base.fields
        fields.title = "Mine"
        do { _ = try await repo.save(fields, over: base, userID: "user-1"); XCTFail() }
        catch { guard case .conflict(let server) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(server.fields.title, "Changed elsewhere") }
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "PATCH" }.count, 1, "no automatic retry over someone else's edit")
    }

    func testUnchangedRevisionWithNoRowsIsAServerRefusal() async throws {
        let transport = handler { request in request.httpMethod == "PATCH" ? (200, json([])) : (200, json([fullRow()])) }
        let repo = try await repository(transport)
        let base = try XCTUnwrap(NewsroomRepository.article(Row(fullRow())))
        var fields = base.fields
        fields.title = "Mine"
        do { _ = try await repo.save(fields, over: base, userID: "user-1"); XCTFail() }
        catch { guard case .platform(.forbidden) = error else { return XCTFail("\(error)") } }
    }

    func testRowLevelSecurityDenialIsForbidden() async throws {
        let transport = handler { _ in (403, json(["code": "42501", "message": "new row violates row-level security policy"])) }
        let repo = try await repository(transport)
        let base = try XCTUnwrap(NewsroomRepository.article(Row(fullRow())))
        var fields = base.fields
        fields.title = "Mine"
        do { _ = try await repo.save(fields, over: base, userID: "user-1"); XCTFail() }
        catch { guard case .platform(.forbidden) = error else { return XCTFail("\(error)") } }
    }

    func testStatusChangeRecordsAVersionLikeTheWebsite() async throws {
        let transport = handler { request in
            if request.path.hasSuffix("news_article_versions") { return (201, Data()) }
            return (200, json([fullRow(revision: "2026-11-10T12:00:00+00:00", status: "in_review")]))
        }
        let repo = try await repository(transport)
        let base = try XCTUnwrap(NewsroomRepository.article(Row(fullRow())))
        let result = try await repo.save(base.fields, over: base, status: .inReview, userID: "user-1")
        XCTAssertTrue(result.versionRecorded)
        let patch = try XCTUnwrap(transport.requests.first { $0.httpMethod == "PATCH" })
        XCTAssertEqual(patch.bodyObject["status"] as? String, "in_review")
        let version = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(version.path, "/rest/v1/news_article_versions")
        XCTAssertEqual(version.bodyObject["article_id"] as? String, articleID)
        XCTAssertEqual(version.bodyObject["created_by"] as? String, "user-1")
    }

    func testScheduledPublicationSendsTheChosenTime() async throws {
        let when = fixedNow.addingTimeInterval(86_400)
        let transport = handler { request in
            request.path.hasSuffix("versions") ? (201, Data()) : (200, json([fullRow(status: "published")]))
        }
        let repo = try await repository(transport)
        let base = try XCTUnwrap(NewsroomRepository.article(Row(fullRow(status: "approved"))))
        _ = try await repo.save(base.fields, over: base, status: .published, publishedAt: when, userID: "user-1")
        let patch = try XCTUnwrap(transport.requests.first { $0.httpMethod == "PATCH" })
        XCTAssertEqual(patch.bodyObject["published_at"] as? String, HCGJSON.formatDate(when))
    }

    func testCreateDraftMatchesTheWebsite() async throws {
        let transport = handler { _ in (201, json([fullRow(title: "Untitled article")])) }
        let repo = try await repository(transport)
        _ = try await repo.createDraft(userID: "user-1")
        let insert = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(insert.httpMethod, "POST")
        XCTAssertEqual(insert.bodyObject["status"] as? String, "draft")
        XCTAssertEqual(insert.bodyObject["created_by"] as? String, "user-1")
        XCTAssertTrue((insert.bodyObject["slug"] as? String ?? "").hasPrefix("draft-"))
    }

    func testMediaUploadSignsRecordsAndRollsBackWhenTheRecordFails() async throws {
        let transport = handler { request in
            switch (request.httpMethod ?? "", request.path) {
            case ("POST", let p) where p.hasPrefix("/storage/v1/object/sign/"): return (200, json(["signedURL": "/object/sign/hcg-news-media/x?token=t"]))
            case ("POST", let p) where p.hasPrefix("/storage/v1/object/"): return (200, json(["Key": "x"]))
            case ("POST", "/rest/v1/news_media"): return (403, json(["code": "42501", "message": "row-level security"]))
            case ("DELETE", _): return (200, json([]))
            default: return (500, Data())
            }
        }
        let repo = try await repository(transport)
        do {
            _ = try await repo.upload(data: Data(repeating: 1, count: 10), mimeType: "image/jpeg", fileExtension: "JPG",
                                      articleID: articleID, userID: "user-1", caption: "c", altText: "a", credit: "cr")
            XCTFail()
        } catch let e as PlatformError { guard case .forbidden = e else { return XCTFail("\(e)") } }
        let upload = try XCTUnwrap(transport.requests.first { $0.path.hasPrefix("/storage/v1/object/hcg-news-media/") })
        XCTAssertTrue(upload.path.hasPrefix("/storage/v1/object/hcg-news-media/articles/\(articleID)/images/"))
        XCTAssertTrue(upload.path.hasSuffix(".jpg"))
        XCTAssertEqual(upload.value(forHTTPHeaderField: "x-upsert"), "false")
        let sign = try XCTUnwrap(transport.requests.first { $0.path.contains("/object/sign/") })
        XCTAssertEqual(sign.bodyObject["expiresIn"] as? Int, 315_360_000)
        let delete = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(delete.httpMethod, "DELETE")
        XCTAssertEqual((delete.bodyObject["prefixes"] as? [String])?.first.map { upload.path.hasSuffix($0) }, true)
    }

    func testUploadValidationMatchesTheWebsite() {
        XCTAssertNil(NewsroomRepository.uploadProblem(mimeType: "image/png", byteCount: 1000))
        XCTAssertNotNil(NewsroomRepository.uploadProblem(mimeType: "image/png", byteCount: 21 * 1024 * 1024))
        XCTAssertNil(NewsroomRepository.uploadProblem(mimeType: "video/mp4", byteCount: 400 * 1024 * 1024))
        XCTAssertNotNil(NewsroomRepository.uploadProblem(mimeType: "application/pdf", byteCount: 10))
        XCTAssertNotNil(NewsroomRepository.uploadProblem(mimeType: "image/png", byteCount: 0))
        XCTAssertEqual(NewsroomRepository.storagePath(mimeType: "video/mp4", fileExtension: "MP4", articleID: nil,
                                                     id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
                       "library/videos/00000000-0000-0000-0000-000000000001.mp4")
    }

    func testSlugAndPublicationRulesMatchTheWebsite() {
        XCTAssertEqual(NewsroomArticleFields.slugify("  Ærlig talt: Økonomi & Café —  2026! "), "rlig-talt-konomi-cafe-2026")
        XCTAssertEqual(NewsroomArticleFields.slugify(String(repeating: "ab ", count: 60)).count, 90)
        var fields = NewsroomArticleFields(title: "T", slug: "t", body: "<p> </p>")
        XCTAssertEqual(fields.publicationProblems, ["Choose a section before publishing.",
                                                    "Complete the headline, article body and slug before publishing."])
        fields.categoryID = "c1"
        fields.body = "<p>Text</p>"
        XCTAssertTrue(fields.publicationProblems.isEmpty)
    }
}

let testArticleID = "44444444-4444-4444-4444-444444444444"

func fullRow(revision: String = "2026-11-10T09:00:00.123456+00:00", status: String = "draft", title: String = "Test draft — not for publication") -> [String: Any] {
    ["id": testArticleID, "title": title, "subtitle": NSNull(), "slug": "test-draft", "excerpt": NSNull(),
     "body": "<p>Fictional test body.</p>", "status": status, "content_type": "news", "published_at": NSNull(),
     "created_at": "2026-11-09T09:00:00+00:00", "updated_at": revision, "created_by": "user-1",
     "author_id": NSNull(), "category_id": "c1", "featured_image_url": NSNull(), "featured_image_alt": NSNull(),
     "featured_image_caption": NSNull(), "featured_image_credit": NSNull(), "is_featured": false, "is_breaking": false,
     "is_demo": false, "seo_title": NSNull(), "seo_description": NSNull(), "tags": ["test"], "sources": NSNull(),
     "correction_notes": NSNull(), "view_count": 0, "reading_time": 1]
}

