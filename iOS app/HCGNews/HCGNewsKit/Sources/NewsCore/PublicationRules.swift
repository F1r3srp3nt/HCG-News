import Foundation

/// Client-side defence in depth for publication visibility.
///
/// The backend is the authority: it must never send drafts, scheduled or private
/// content to a public client. These rules exist so that a backend mistake does
/// not turn into the app displaying unpublished work. They fail closed.
public enum PublicationVisibility {
    /// Allowed clock skew between device and server for "published in the future".
    public static let clockSkewAllowance: TimeInterval = 5 * 60

    public enum Decision: Equatable, Sendable {
        /// Readable by anyone.
        case visible
        /// Listed, but reading requires an authorised HCG sign-in (explicit backend marking).
        case restricted
        /// Must not be shown at all.
        case hidden(reason: String)
    }

    public static func decision(for item: ArticleSummary, now: Date = Date()) -> Decision {
        if let status = item.status?.lowercased(), status != "published" {
            return .hidden(reason: "status \(status)")
        }
        guard let published = item.publishedAt else {
            return .hidden(reason: "no publication date")
        }
        if published.timeIntervalSince(now) > clockSkewAllowance {
            return .hidden(reason: "scheduled")
        }
        if item.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .hidden(reason: "no headline")
        }
        switch item.access {
        case .public: return .visible
        case .restricted: return .restricted
        case .unknown(let value): return .hidden(reason: "unknown access \(value)")
        }
    }

    /// Keeps visible and restricted items, preserving order, dropping duplicates by id.
    public static func filter(_ items: [ArticleSummary], now: Date = Date()) -> [ArticleSummary] {
        var seen = Set<ArticleID>()
        return items.filter { item in
            guard seen.insert(item.id).inserted else { return false }
            if case .hidden = decision(for: item, now: now) { return false }
            return true
        }
    }
}

/// Breaking news comes only from an explicit backend flag.
///
/// An article is breaking if and only if the backend set `breaking.active == true`
/// and the optional editor-chosen expiry has not passed. Recency alone never makes
/// an article breaking.
public enum BreakingNewsRule {
    public static let maximumItems = 5

    public static func isBreaking(_ item: ArticleSummary, now: Date = Date()) -> Bool {
        guard !item.isDemo, let flag = item.breaking, flag.active else { return false }
        if let expiry = flag.expiresAt, expiry <= now { return false }
        return true
    }

    /// Selects breaking items from any backend-supplied lists (e.g. `home.breaking`
    /// and `home.latest`), newest first, visibility-filtered, at most `maximumItems`.
    public static func select(from lists: [[ArticleSummary]], now: Date = Date()) -> [ArticleSummary] {
        let candidates = PublicationVisibility.filter(lists.flatMap { $0 }, now: now)
            .filter { isBreaking($0, now: now) }
        return Array(candidates
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .prefix(maximumItems))
    }
}

/// Searches articles already loaded in this session when the backend offers no search.
/// The UI must label results as limited to loaded articles.
public enum LocalArticleSearch {
    public static func normalise(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func search(_ query: String, in items: [ArticleSummary]) -> [ArticleSummary] {
        let terms = normalise(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !terms.isEmpty else { return [] }
        return items.filter { item in
            let haystack = normalise([
                item.headline, item.standfirst ?? "", item.section?.name ?? "",
                item.editorialType?.label ?? "", item.bylineNames ?? "",
            ].joined(separator: " "))
            return terms.allSatisfy { haystack.contains($0) }
        }
    }
}
