import Foundation

/// A run of inline text with formatting. Links are only ever http(s) or mailto.
public struct InlineRun: Hashable, Codable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var code: Bool
    public var link: URL?

    public init(_ text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, link: URL? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.code = code
        self.link = link
    }

    func sameStyle(as other: InlineRun) -> Bool {
        bold == other.bold && italic == other.italic && code == other.code && link == other.link
    }
}

/// Formatted inline text (a paragraph, heading, list item, caption...).
public struct InlineText: Hashable, Codable, Sendable {
    public var runs: [InlineRun]

    public init(_ runs: [InlineRun] = []) { self.runs = runs }
    public init(plain: String) { self.runs = plain.isEmpty ? [] : [InlineRun(plain)] }

    public var plainText: String { runs.map(\.text).joined() }
    public var isBlank: Bool { plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var links: [URL] { runs.compactMap(\.link) }
}

public struct ListItem: Hashable, Codable, Sendable {
    public var text: InlineText
    /// Nesting depth, 0 for top level.
    public var level: Int

    public init(text: InlineText, level: Int = 0) {
        self.text = text
        self.level = level
    }
}

/// Native, inert article content. Nothing here can execute code.
public enum ContentBlock: Hashable, Sendable {
    case heading(level: Int, text: InlineText)
    case paragraph(InlineText)
    case list(ordered: Bool, items: [ListItem])
    case quote(paragraphs: [InlineText], attribution: String?)
    case image(ArticleImage)
    case divider
    /// Embedded third-party content (video, social post, iframe) that the app
    /// deliberately does not load. Rendered as a notice with a link to the web article.
    case embedNotice(host: String?)
    /// A block type this version cannot display. Rendered as a clear notice so the
    /// reader knows something is missing; the rest of the article still renders.
    case unsupported(type: String)
}

/// Link and image URL rules for untrusted article content.
public enum LinkPolicy {
    /// Allowed schemes for links the reader can tap.
    public static let allowedLinkSchemes: Set<String> = ["https", "http", "mailto"]

    /// Returns the URL if its scheme is allowed; otherwise nil (text is kept, link dropped).
    public static func allowedExternalURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), allowedLinkSchemes.contains(scheme) else { return nil }
        if scheme == "mailto" { return url }
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Resolves an href from article HTML. Relative URLs resolve against `base`.
    public static func resolveLink(_ raw: String, base: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        // Reject control characters and whitespace-obfuscated schemes ("java\tscript:").
        let compact = trimmed.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }
        let compactString = String(String.UnicodeScalarView(compact))
        guard let url = URL(string: compactString, relativeTo: base)?.absoluteURL else { return nil }
        return allowedExternalURL(url)
    }

    /// Images must be HTTPS (relative paths resolve against `base`).
    public static func resolveImage(_ raw: String, base: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
