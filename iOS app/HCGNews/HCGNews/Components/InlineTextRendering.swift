import SwiftUI
import NewsCore

extension InlineText {
    /// Converts sanitised inline runs to an AttributedString. Only bold, italic,
    /// underline, code and http(s)/mailto links exist at this point; nothing executable.
    var attributed: AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.bold { intent.insert(.stronglyEmphasized) }
            if run.italic { intent.insert(.emphasized) }
            if run.code { intent.insert(.code) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if run.underline {
                piece[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = .single
            }
            if let link = run.link, LinkPolicy.allowedExternalURL(link) != nil {
                piece.link = link
                // Underlined as well as tinted, so links don't rely on colour alone.
                piece[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = .single
            }
            result.append(piece)
        }
        return result
    }
}

/// Restricts what tapping a link can do: only web and mail links leave the app,
/// through the system (Safari / Mail). Anything else is discarded.
struct SafeLinkHandling: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            LinkPolicy.allowedExternalURL(url) != nil ? .systemAction : .discarded
        })
    }
}

extension View {
    func safeLinkHandling() -> some View { modifier(SafeLinkHandling()) }
}
