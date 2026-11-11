import SwiftUI
import NewsCore

/// Renders one sanitised content block natively. No web view, no scripts.
struct ContentBlockView: View {
    let block: ContentBlock
    let canonicalURL: URL?

    @Environment(\.palette) private var palette
    @Environment(\.readerStyle) private var readerStyle

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(text.attributed)
                .font(Typography.headline(level <= 2 ? .title2 : (level == 3 ? .title3 : .headline), weight: .bold))
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            Text(text.attributed)
                .font(Typography.body(for: readerStyle))
                .foregroundStyle(palette.primaryText)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker(ordered: ordered, index: index, items: items))
                            .font(Typography.body(for: readerStyle).monospacedDigit())
                            .foregroundStyle(palette.secondaryText)
                            .accessibilityHidden(true)
                        Text(item.text.attributed)
                            .font(Typography.body(for: readerStyle))
                            .foregroundStyle(palette.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.level) * 20)
                    .accessibilityElement(children: .combine)
                }
            }

        case .quote(let paragraphs, let attribution):
            HStack(alignment: .top, spacing: 14) {
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph.attributed)
                            .font(Typography.headline(.title3, weight: .regular).italic())
                            .foregroundStyle(palette.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let attribution, !attribution.isEmpty {
                        Text("— \(attribution)")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(quoteLabel(paragraphs, attribution))

        case .image(let image):
            ArticleFigure(image: image)

        case .divider:
            Rectangle().fill(palette.separator).frame(height: 1)
                .accessibilityHidden(true)

        case .embedNotice(let host):
            VStack(alignment: .leading, spacing: 8) {
                Label("Embedded content not shown", systemImage: "rectangle.dashed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text(embedMessage(host: host))
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let canonicalURL {
                    Link("View the full article on the web", destination: canonicalURL)
                        .font(.footnote.weight(.semibold))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func marker(ordered: Bool, index: Int, items: [ListItem]) -> String {
        if ordered { return String(number(for: index, in: items)) + "." }
        return items[index].level == 0 ? "•" : "◦"
    }

    private func embedMessage(host: String?) -> String {
        let source = host.map { " from " + $0 } ?? ""
        return "This article includes embedded content" + source + ". For your security, the app doesn't load embedded third-party content."
    }

    /// Numbering restarts per nesting level.
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
