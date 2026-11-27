import SwiftUI

// The HCG News brand, as on news.hakmicapitalgroup.com:
// [HCG logo] | News — the edition's official HCG logo (transparent; dark lettering in
// Light, silver in Dark), a hairline vertical separator, and "News" in italic Newsreader.
// The logo artwork is shown at its own proportions and never re-drawn or stretched.

/// The edition's official HCG logo.
struct HCGMark: View {
    var height: CGFloat = 28
    @Environment(\.edition) private var edition

    var body: some View {
        Image(edition.logoAsset)
            .resizable()
            .interpolation(.high)
            .aspectRatio(edition.logoAspectRatio, contentMode: .fit)
            .frame(height: height)
            .accessibilityLabel("HCG")
    }
}

/// "HCG | News": logo, separator, italic serif wordmark.
struct NewsWordmark: View {
    var logoHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    var body: some View {
        let h = min(logoHeight * scale, logoHeight * 1.6)
        HStack(alignment: .center, spacing: h * 0.33) {
            HCGMark(height: h)
            Rectangle()
                .fill(Palette.separator)
                .frame(width: 1, height: h * 0.9)
            Text("News")
                .font(Self.wordmarkFont(size: h * 0.82))
                .foregroundStyle(Palette.primaryText)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HCG News")
    }

    /// Italic Newsreader at the logo's scale (the system italic serif if it can't load).
    static func wordmarkFont(size: CGFloat) -> Font {
        let name = BrandFonts.newsreader(.regular, italic: true)
        return BrandFonts.available(name) ? .custom(name, fixedSize: size) : .system(size: size, design: .serif).italic()
    }
}

/// The publication masthead at the top of Home, after the website's header and hero.
struct Masthead: View {
    @Environment(\.edition) private var edition
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Date line, header tagline and edition label.
            dateLine
                .padding(.vertical, 8)
            Rectangle().fill(Palette.separator).frame(height: 1).accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                NewsWordmark(logoHeight: sizeClass == .regular ? 40 : 32)
                Text("A HAKMI CAPITAL GROUP PUBLICATION")
                    .font(Typography.sans(.caption2, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.top, 16)

            hero
                .padding(.top, 18)
        }
        .padding(.horizontal, sizeClass == .regular ? 32 : 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("HCG News, \(edition.editionName). \(NewsDate.day(Date())). The future of information.")
        .accessibilityAddTraits(.isHeader)
    }

    private var dateLine: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Text(NewsDate.day(Date()))
                .font(Typography.sans(.caption))
                .foregroundStyle(Palette.secondaryText)
            if edition == .future {
                Label {
                    Text(edition.editionName.uppercased())
                } icon: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(Palette.accent)
                }
                .font(Typography.kicker)
                .foregroundStyle(Palette.silver)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
    }

    /// Classic: the "HCG News." wordmark hero. Future: the command-centre backdrop.
    @ViewBuilder
    private var hero: some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            Text("HAKMI CAPITAL GROUP")
                .font(Typography.kicker)
                .foregroundStyle(Palette.accent)
            if edition == .classic {
                (Text("HCG News") + Text(".").foregroundColor(Palette.accent))
                    .font(Typography.headline(sizeClass == .regular ? .largeTitle : .title, weight: .medium))
                    .foregroundStyle(Palette.primaryText)
            }
            Text("The future of information.")
                .font(Typography.serifItalic(.title3))
                .foregroundStyle(edition == .future && colorScheme == .dark ? Color.white.opacity(0.88) : Palette.silver)
            Text("Technology, business, markets and the ideas shaping tomorrow.")
                .font(Typography.sans(.footnote))
                .foregroundStyle(edition == .future && colorScheme == .dark ? Color.white.opacity(0.72) : Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if edition == .future {
            content
                .padding(.vertical, sizeClass == .regular ? 36 : 24)
                .padding(.horizontal, 16)
                .background { FutureBackdrop() }
                .clipShape(RoundedRectangle(cornerRadius: edition.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: edition.cornerRadius, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: 1))
        } else {
            content
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Palette.primaryText).frame(height: 2).offset(y: 10).accessibilityHidden(true)
                }
                .padding(.bottom, 10)
        }
    }
}

/// The Future Edition's command-centre backdrop (from the website), shaded so text stays
/// legible. In Light appearance, a quiet signal-tinted surface instead.
struct FutureBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            Image("FutureCommandCenter")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay(
                    LinearGradient(colors: [Color.black.opacity(0.92), Color.black.opacity(0.62), Color.black.opacity(0.25)],
                                   startPoint: .leading, endPoint: .trailing))
                .overlay(LinearGradient(colors: [Color.black.opacity(0.7), .clear], startPoint: .bottom, endPoint: .center))
                .accessibilityHidden(true)
        } else {
            ZStack {
                Palette.surface
                RadialGradient(colors: [Palette.accent.opacity(0.16), .clear], center: UnitPoint(x: 0.75, y: 0.25),
                               startRadius: 0, endRadius: 320)
            }
            .accessibilityHidden(true)
        }
    }
}

/// A compact title for navigation bars: "HCG | News".
struct CompactMasthead: View {
    var body: some View {
        NewsWordmark(logoHeight: 20)
    }
}

/// "A Hakmi Capital Group publication", with the classic HCG mark.
struct PublisherAttribution: View {
    var large = false

    var body: some View {
        VStack(spacing: 10) {
            Image("HCGClassicLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(EditionChoice.classic.logoAspectRatio, contentMode: .fit)
                .frame(height: large ? 56 : 32)
                .accessibilityHidden(true)
            Text("A Hakmi Capital Group publication")
                .font(Typography.sans(.footnote))
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A Hakmi Capital Group publication")
    }
}
