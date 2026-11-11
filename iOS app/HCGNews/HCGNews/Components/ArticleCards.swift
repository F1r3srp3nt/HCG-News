import SwiftUI
import NewsCore

/// "ANALYSIS · Norwegian Politics" — the editorial type is always shown when supplied.
struct KickerLine: View {
    let editorialType: EditorialType?
    let sectionName: String?
    var restricted = false

    @Environment(\.palette) private var palette

    var body: some View {
        let parts = [editorialType?.label.uppercased(), sectionName].compactMap { $0 }
        if !parts.isEmpty || restricted {
            HStack(spacing: 6) {
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(Typography.kicker)
                        .foregroundStyle(editorialType == nil ? palette.secondaryText : palette.accent)
                }
                if restricted {
                    Label("HCG sign-in", systemImage: "lock.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
    }
}

/// "By A · 3 Nov 2026"
struct MetaLine: View {
    let summary: ArticleSummary
    @Environment(\.palette) private var palette

    var body: some View {
        let parts = [summary.bylineNames.map { "By \($0)" }, summary.publishedAt.map { NewsDate.short($0) }].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(Typography.meta)
                .foregroundStyle(palette.secondaryText)
        }
    }
}

enum CardAccessibility {
    static func label(_ s: ArticleSummary) -> String {
        var parts: [String] = []
        if let type = s.editorialType { parts.append(type.label) }
        parts.append(s.headline)
        if let section = s.section?.name { parts.append("Section: \(section)") }
        if let byline = s.bylineNames { parts.append("By \(byline)") }
        if let date = s.publishedAt { parts.append(NewsDate.full(date)) }
        if s.access == .restricted { parts.append("Requires HCG sign-in") }
        return parts.joined(separator: ". ")
    }
}

/// Large card for the lead/featured story. Image above (compact) or beside
/// (regular width) the live headline; never overlaid.
struct LeadArticleCard: View {
    let summary: ArticleSummary
    var wide: Bool

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = (wide && !typeSize.isAccessibilitySize)
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
        layout {
            if let image = summary.image {
                ArticleImageView(image: image)
                    .frame(maxWidth: wide ? 520 : .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                KickerLine(editorialType: summary.editorialType, sectionName: summary.section?.name,
                           restricted: summary.access == .restricted)
                Text(summary.headline)
                    .font(Typography.headline(wide ? .largeTitle : .title, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let standfirst = summary.standfirst {
                    Text(standfirst)
                        .font(.body)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                MetaLine(summary: summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CardAccessibility.label(summary))
        .accessibilityHint("Opens the article")
    }
}

/// Standard list row. Thumbnail (if any) keeps its proportions in a bounded box;
/// at accessibility text sizes the image moves above the text.
struct ArticleRow: View {
    let summary: ArticleSummary
    var showsStandfirst = true

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var thumbWidth: CGFloat = 104

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        layout {
            VStack(alignment: .leading, spacing: 6) {
                KickerLine(editorialType: summary.editorialType, sectionName: summary.section?.name,
                           restricted: summary.access == .restricted)
                Text(summary.headline)
                    .font(Typography.headline(.title3))
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if showsStandfirst, let standfirst = summary.standfirst {
                    Text(standfirst)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(stacked ? nil : 3)
                }
                MetaLine(summary: summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let image = summary.image {
                ArticleImageView(image: image, maxHeight: stacked ? nil : thumbWidth * 1.25, cornerRadius: 4)
                    .frame(width: stacked ? nil : min(thumbWidth, 160))
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CardAccessibility.label(summary))
        .accessibilityHint("Opens the article")
    }
}

/// Section header used in feeds.
struct FeedHeader: View {
    let title: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(.footnote, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(palette.accent)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(palette.separator).frame(height: 1)
        }
        .padding(.top, 20)
    }
}
