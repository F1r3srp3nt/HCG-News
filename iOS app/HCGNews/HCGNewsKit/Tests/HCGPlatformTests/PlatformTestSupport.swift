import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HCGTransport
import HCGConnect
import NewsCore
@testable import HCGPlatform

// Fictional rows only. Nothing here is HCG News reporting.

let testAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFnZ2R5em95ZHZlYWZrbWpna3BxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1ODQwODQsImV4cCI6MjA5ODE2MDA4NH0.OLbNhV_hvWwS_BqgYVxwU9TZ9P05lX2Fp-ake-hAJ4M"

let testPlatform = HCGPlatformConfiguration(
    environment: "test", projectURL: URL(string: "https://qggdyzoydveafkmjgkpq.supabase.co")!,
    publicClientKey: testAnonKey, websiteURL: URL(string: "https://beta.hakmicapitalgroup.com")!,
    publicationURL: URL(string: "https://news.hakmicapitalgroup.com")!)

let fixedNow = Date(timeIntervalSince1970: 1_793_000_000)

final class MemorySessionStore: ConnectSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ConnectSession?
    init(_ session: ConnectSession? = nil) { stored = session }
    func load() throws -> ConnectSession? { lock.withLock { stored } }
    func save(_ session: ConnectSession) throws { lock.withLock { stored = session } }
    func delete() throws { lock.withLock { stored = nil } }
    var current: ConnectSession? { lock.withLock { stored } }
}

func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }

func articleRow(id: String = UUID().uuidString.lowercased(), title: String = "Fixture headline", status: String = "published",
                publishedAt: Date = fixedNow.addingTimeInterval(-3600), breaking: Bool = false, demo: Bool = false,
                extra: [String: Any] = [:]) -> [String: Any] {
    var row: [String: Any] = [
        "id": id, "title": title, "subtitle": NSNull(), "slug": "fixture-\(id.prefix(8))", "excerpt": "Fictional excerpt.",
        "status": status, "content_type": "analysis", "published_at": HCGJSON.formatDate(publishedAt),
        "updated_at": "2026-11-10T09:00:00.123456+00:00",
        "featured_image_url": "https://qggdyzoydveafkmjgkpq.supabase.co/storage/v1/object/sign/hcg-news-media/x.jpg?token=t",
        "featured_image_alt": "Alt", "featured_image_caption": NSNull(), "featured_image_credit": "Credit",
        "is_featured": false, "is_breaking": breaking, "is_demo": demo, "reading_time": 3,
        "category": ["id": "c1", "name": "Markets", "slug": "markets"],
        "author": ["id": PublicationDisclosures.founderAuthorID, "name": "Fixture Author", "slug": "fixture", "title": NSNull()],
    ]
    for (k, v) in extra { row[k] = v }
    return row
}

func tokenResponse(user: String = "user-1", email: String = "staff@example.test", access: String = "access-1",
                   refresh: String = "refresh-1", expiresIn: Double = 3600) -> Data {
    json(["access_token": access, "refresh_token": refresh, "expires_in": expiresIn, "token_type": "bearer",
          "user": ["id": user, "email": email, "user_metadata": ["display_name": "Fixture Staff"]]])
}

extension URLRequest {
    var path: String { url?.path ?? "" }
    var query: [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] { out[item.name] = item.value ?? "" }
        return out
    }
    var bodyObject: [String: Any] {
        guard let body = httpBody else { return [:] }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }
    var bearer: String? { value(forHTTPHeaderField: "Authorization").map { String($0.dropFirst("Bearer ".count)) } }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}
