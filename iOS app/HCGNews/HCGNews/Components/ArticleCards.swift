import SwiftUI
import NewsCore
import NewsAppModel

/// The editorial-type label (News, Analysis, Opinion, Sponsored, HCG Announcement,
/// or an unknown type verbatim). Sponsored is always visibly distinct.
struct EditorialLabel: View {
    let type: EditorialType

    var body: some View {
        Text(type.label.uppercased())
            .font(Typography.kicker)
            .tracking(0.8)
            .foregroundStyle(type == .sponsored ? Palette.warning : Palette.primaryText)
            .padding(.horizontal, type == .sponsored ? 6 : 0)
            .padding(.vertical, type == .sponsored ? 2 : 0)
            .overlay {
                if type == .sponsored {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.warning, lineWidth: 1)
                }
            }
            .accessibilityLabel(type == .sponsored ? "Sponsored content" : type.label)
    }
}

/// "ANALYSIS · Norwegian Politics" plus restriction and download state.
struct KickerLine: View {
    let editorialType: EditorialType?
    let sectionName: String?
    var restricted = false
    var download: OfflineEntry?

    var body: some View {
        HStack(spacing: 6) {
            if let editorialType { EditorialLabel(type: editorialType) }
            if let sectionName {
                if editorialType != nil { Text("·").foregroundStyle(Palette.silver).accessibilityHidden(true) }
                Text(sectionName).font(Typography.kicker).foregroundStyle(Palette.secondaryText)
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

/// "By A · 3 Nov 2026"
struct MetaLine: View {
    let summary: ArticleSummary

    var body: some View {
        let parts = [summary.bylineNames.map { "By \($0)" }, summary.publishedAt.map { NewsDate.short($0) }].compactMap { $0 }
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

/// Large lead card. Image above (compact) or beside (regular width) the live
/// headline; never overlaid.
struct LeadArticleCard: View {
    let summary: ArticleSummary
    var wide: Bool
    var download: OfflineEntry?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = (wide && !typeSize.isAccessibilitySize)
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 28))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
        layout {
            if let image = summary.image {
                ArticleImageView(image: image).frame(maxWidth: wide ? 560 : .infinity)
            }
            VStack(alignment: .leading, spacing: 10) {
                KickerLine(editorialType: summary.editorialType, sectionName: summary.section?.name,
                           restricted: summary.access == .restricted, download: download)
                Text(summary.headline)
                    .font(Typography.headline(wide ? .largeTitle : .title, weight: .bold))
                    .foregroundStyle(Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let standfirst = summary.standfirst {
                    Text(standfirst)
                        .font(Typography.headline(.body, weight: .regular))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                MetaLine(summary: summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CardAccessibility.label(summary, download: download))
        .accessibilityHint("Opens the article")
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
                           restricted: summary.access == .restricted, download: download)
                Text(summary.headline)
                    .font(Typography.headline(.title3))
                    .foregroundStyle(Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if showsStandfirst, let standfirst = summary.standfirst {
                    Text(standfirst)
                        .font(.subheadline)
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

/// Section heading with a silver rule.
struct FeedHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(Typography.sectionTitle)
                    .tracking(1.4)
                    .foregroundStyle(Palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let trailing {
                    Text(trailing).font(.caption).foregroundStyle(Palette.secondaryText)
                }
            }
            Rectangle().fill(Palette.primaryText).frame(height: 2)
        }
        .padding(.top, 22)
    }
}

struct RowSeparator: View {
    var body: some View { Rectangle().fill(Palette.separator).frame(height: 1).accessibilityHidden(true) }
}
