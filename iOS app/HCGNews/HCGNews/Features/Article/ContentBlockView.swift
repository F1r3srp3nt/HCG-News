import SwiftUI
import NewsCore

/// Renders one sanitised content block natively. No web view, no scripts.
/// Unsupported content degrades to a visible notice; the rest of the article still renders.
struct ContentBlockView: View {
    let block: ContentBlock
    let canonicalURL: URL?
    var typeface: ArticleTypeface = .serif
    var lineSpacing: CGFloat = 6

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(text.attributed)
                .font(Typography.headline(level <= 2 ? .title2 : (level == 3 ? .title3 : .headline), weight: .bold))
                .foregroundStyle(Palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            Text(text.attributed)
                .font(Typography.body(typeface))
                .foregroundStyle(Palette.primaryText)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker(ordered: ordered, index: index, items: items))
                            .font(Typography.body(typeface).monospacedDigit())
                            .foregroundStyle(Palette.silver)
                            .accessibilityHidden(true)
                        Text(item.text.attributed)
                            .font(Typography.body(typeface))
                            .foregroundStyle(Palette.primaryText)
                            .lineSpacing(lineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(item.level) * 20)
                    .accessibilityElement(children: .combine)
                }
            }

        case .quote(let paragraphs, let attribution):
            HStack(alignment: .top, spacing: 14) {
                Rectangle().fill(Palette.silver).frame(width: 3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph.attributed)
                            .font(Typography.headline(.title3, weight: .regular).italic())
                            .foregroundStyle(Palette.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if let attribution, !attribution.isEmpty {
                        Text("— \(attribution)").font(.subheadline).foregroundStyle(Palette.secondaryText)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(quoteLabel(paragraphs, attribution))

        case .image(let image):
            ArticleFigure(image: image)

        case .divider:
            Rectangle().fill(Palette.separator).frame(height: 1).accessibilityHidden(true)

        case .embedNotice(let host):
            notice(title: "Embedded content not shown", icon: "rectangle.dashed",
                   text: embedText(host))

        case .unsupported(let type):
            notice(title: "Part of this article can't be shown in the app", icon: "square.dashed",
                   text: "This version of HCG News doesn't support “\(type)” content. The rest of the article is shown below.")
        }
    }

    private func notice(title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.primaryText)
            Text(text).font(.footnote).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            if let canonicalURL {
                Link("View the full article on the web", destination: canonicalURL).font(.footnote.weight(.semibold))
            }
        }
        .cardSurface(cornerRadius: 10)
    }

    private func embedText(_ host: String?) -> String {
        let source = host.map { " from " + $0 } ?? ""
        return "This article includes embedded content" + source + ". For your security, the app doesn't load embedded third-party content."
    }

    private func marker(ordered: Bool, index: Int, items: [ListItem]) -> String {
        if ordered { return String(number(for: index, in: items)) + "." }
        return items[index].level == 0 ? "•" : "◦"
    }

    private func number(for index: Int, in items: [ListItem]) -> Int {
        let level = items[index].level
        var count = 0
        for i in stride(from: index, through: 0, by: -1) {
            if items[i].level < level { break }
            if items[i].level == level { count += 1 }
        }
        return count
    }

    private func quoteLabel(_ paragraphs: [InlineText], _ attribution: String?) -> String {
        let text = paragraphs.map(\.plainText).joined(separator: " ")
        if let attribution, !attribution.isEmpty { return "Quote: \(text). \(attribution)" }
        return "Quote: \(text)"
    }
}
