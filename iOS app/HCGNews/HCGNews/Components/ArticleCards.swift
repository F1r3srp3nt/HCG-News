import SwiftUI
import NewsCore
import NewsAppModel

/// The editorial-type tag, bordered as on the website. Sponsored is always visibly
/// distinct (warning outline); HCG Announcement uses the metal outline.
struct EditorialLabel: View {
    let type: EditorialType

    var body: some View {
        let colour: Color = type == .sponsored ? Palette.warning : (type == .announcement ? Palette.silver : Palette.secondaryText)
        Text(type.label.uppercased())
            .font(Typography.sans(.caption2, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(colour)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(colour.opacity(0.6), lineWidth: 1))
            .accessibilityLabel(type == .sponsored ? "Sponsored content" : type.label)
    }
}

/// "ARTIFICIAL INTELLIGENCE [ANALYSIS]": the section eyebrow, the type tag, then the
/// demo, restriction and download marks.
struct KickerLine: View {
    let editorialType: EditorialType?
    let sectionName: String?
    var restricted = false
    var download: OfflineEntry?
    /// The publication's "Demo content" marking.
    var isDemo = false

    var body: some View {
        HStack(spacing: 8) {
            if let sectionName {
                Text(sectionName.uppercased()).font(Typography.kicker).foregroundStyle(Palette.silver)
            }
            if let editorialType { EditorialLabel(type: editorialType) }
            if isDemo {
                Text("DEMO CONTENT")
                    .font(Typography.sans(.caption2, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.silver, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    .accessibilityLabel("Demo content")
            }
            if restricted {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Palette.silver)
                    .accessibilityLabel("Requires HCG sign-in")
            }
            if let download, download.hasCompleteCopy {
                Image(systemName: download.updateAvailable ? "arrow.down.circle.dotted" : "arrow.down.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel(download.updateAvailable ? "Downloaded, update available" : "Downloaded")
            }
        }
    }
}

/// "By Author · 27 Nov 2026", as on the website.
struct MetaLine: View {
    let summary: ArticleSummary

    var body: some View {
        let parts = [summary.bylineNames.map { "By \($0)" }, summary.publishedAt.map { NewsDate.article($0) }].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(Typography.meta)
                .foregroundStyle(Palette.secondaryText)
        }
    }
}

enum CardAccessibility {
    static func label(_ s: ArticleSummary, download: OfflineEntry? = nil) -> String {
        var parts: [String] = []
        if let type = s.editorialType { parts.append(type == .sponsored ? "Sponsored content" : type.label) }
        parts.append(s.headline)
        if let section = s.section?.name { parts.append("Section: \(section)") }
        if let byline = s.bylineNames { parts.append("By \(byline)") }
        if let date = s.publishedAt { parts.append(NewsDate.full(date)) }
        if s.access == .restricted { parts.append("Requires HCG sign-in") }
        if download?.hasCompleteCopy == true { parts.append("Downloaded") }
        return parts.joined(separator: ". ")
    }
}

/// The featured story, after the website's story hero: 16:10 image (or the HCG News
/// placeholder), section and type, serif headline, excerpt, byline and date. Beside the
/// image on wide screens; never overlaid on it.
struct LeadArticleCard: View {
    let summary: ArticleSummary
    var wide: Bool
    var download: OfflineEntry?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.edition) private var edition

    var body: some View {
        let sideBySide = wide && !typeSize.isAccessibilitySize
        let layout = sideBySide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        layout {
            Group {
                if let image = summary.image {
                    ArticleImageView(image: image, cornerRadius: 0, fillAspect: 16.0 / 10.0, placeholderSection: summary.section?.name)
                } else {
                    MediaPlaceholder(section: summary.section?.name).aspectRatio(16.0 / 10.0, contentMode: .fit)
                }
            }
            .frame(maxWidth: sideBySide ? 560 : .infinity)
            VStack(alignment: .leading, spacing: 10) {
                KickerLine(editorialType: summary.editorialType, sectionName: summary.section?.name,
                           restricted: summary.access == .restricted, download: download, isDemo: summary.isDemo)
                Text(summary.headline)
                    .font(Typography.headline(wide ? .largeTitle : .title, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let standfirst = summary.standfirst {
                    Text(standfirst)
                        .font(Typography.sans(.body))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                MetaLine(summary: summary)
            }
            .padding(wide ? 24 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .editorialCard(edition)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CardAccessibility.label(summary, download: download))
        .accessibilityHint("Opens the article")
    }
}

/// The website's stream card: 16:10 media, section eyebrow, serif headline, two-line
/// excerpt, byline and date. Used for the Latest grid.
struct StreamCard: View {
    let summary: ArticleSummary
    var download: OfflineEntry?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.edition) private var edition

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let image = summary.image {
                    ArticleImageView(image: image, cornerRadius: 0, fillAspect: 16.0 / 10.0, placeholderSection: summary.section?.name)
                } else {
                    MediaPlaceholder(section: summary.section?.name).aspectRatio(16.0 / 10.0, contentMode: .fit)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                KickerLine(editorialType: summary.editorialType, sectionName: summary.section?.name,
                           restricted: summary.access == .restricted, download: download, isDemo: summary.isDemo)
                Text(summary.headline)
                    .font(Typography.headline(.title3))
                    .foregroundStyle(Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let standfirst = summary.standfirst {
                    Text(standfirst)
                        .font(Typography.sans(.subheadline))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                }
                Spacer(minLength: 0)
                MetaLine(summary: summary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .editorialCard(edition)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CardAccessibility.label(summary, download: download))
        .accessibilityHint("Opens the article")
    }
}

extension View {
    /// Card surface per edition, as on the website: Future, a layered metallic gradient
    /// with a faint silver border; Classic, a flat card with a hairline border.
    func editorialCard(_ edition: EditionChoice) -> some View {
        let shape = RoundedRectangle(cornerRadius: edition.cornerRadius, style: .continuous)
        return background {
            if edition == .future {
                LinearGradient(colors: [Palette.elevated, Palette.surface], startPoint: .top, endPoint: .bottom)
            } else {
                Palette.elevated
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(edition == .future ? Palette.silver.opacity(0.18) : Palette.separator, lineWidth: 1))
    }
}

/// Compact list row. The thumbnail keeps its proportions; at accessibility text
/// sizes it moves above the text.
struct ArticleRow: View {
    let summary: ArticleSummary
    var showsStandfirst = true
    var download: OfflineEntry?

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var thumbWidth: CGFloat = 96

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        layout {
            VStack(alignment: .leading, spacing: 6) {
                KickerLine(editorialType: summary.editorialType, sectionName: summary.section?.name,
                           restricted: summary.access == .restricted, download: download, isDemo: summary.isDemo)
                Text(summary.headline)
                    .font(Typography.headline(.title3))
                    .foregroundStyle(Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if showsStandfirst, let standfirst = summary.standfirst {
                    Text(standfirst)
                        .font(Typography.sans(.subheadline))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(stacked ? nil : 2)
                }
                MetaLine(summary: summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let image = summary.image {
                ArticleImageView(image: image, maxHeight: stacked ? nil : thumbWidth * 1.25, cornerRadius: 4)
                    .frame(width: stacked ? nil : min(thumbWidth, 150))
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CardAccessibility.label(summary, download: download))
        .accessibilityHint("Opens the article")
    }
}

/// Section heading: uppercase eyebrow over a rule (signal dot in the Future Edition).
struct FeedHeader: View {
    let title: String
    var trailing: String?
    @Environment(\.edition) private var edition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if edition == .future {
                    Circle().fill(Palette.accent).frame(width: 6, height: 6).accessibilityHidden(true)
                }
                Text(title.uppercased())
                    .font(Typography.sectionTitle)
                    .tracking(0.8)
                    .foregroundStyle(Palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let trailing {
                    Text(trailing).font(Typography.sans(.caption)).foregroundStyle(Palette.secondaryText)
                }
            }
            Rectangle().fill(edition == .classic ? Palette.primaryText : Palette.separator).frame(height: edition == .classic ? 2 : 1)
        }
        .padding(.top, 26)
        .padding(.bottom, 4)
    }
}

struct RowSeparator: View {
    var body: some View { Rectangle().fill(Palette.separator).frame(height: 1).accessibilityHidden(true) }
}
