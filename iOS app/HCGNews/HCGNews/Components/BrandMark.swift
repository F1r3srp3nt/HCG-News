import SwiftUI

// Logo assets (inspected before use):
// - HCGNewsMark: the HCG logo supplied for this app (silver, cyan light-lines on black;
//   margins trimmed, proportions unchanged). Used for the masthead and compact marks.
// - AppIcon: the supplied HCG News icon set (HCG-News-Icons.zip), installed unchanged;
//   all iPhone, iPad and App Store sizes. Not used inside the app's screens.
// - HCGLogo / HCGLogoTrimmed: the Hakmi Capital Group corporate mark. Used only for
//   publisher attribution ("A Hakmi Capital Group publication").
// The artwork is always shown on its native black ground, at its own aspect ratio.

/// The HCG logo at a given height, on black, never stretched.
struct HCGMark: View {
    var height: CGFloat = 28

    var body: some View {
        Image("HCGNewsMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .accessibilityLabel("HCG")
    }
}

/// The publication masthead: a black band with the HCG logo, the publication name
/// and today's date. Shown at the top of Home.
struct Masthead: View {
    @ScaledMetric(relativeTo: .largeTitle) private var logoHeight: CGFloat = 46
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 10) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
            layout {
                HCGMark(height: min(logoHeight * (sizeClass == .regular ? 1.25 : 1), 90))
                Text("NEWS")
                    .font(.system(sizeClass == .regular ? .largeTitle : .title, design: .serif, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(Color.white)
            }
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1).padding(.horizontal, 24)
            Text(NewsDate.day(Date()))
                .font(.caption.weight(.medium))
                .tracking(1.2)
                .foregroundStyle(Color(white: 0.75))
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Palette.masthead)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HCG News, \(NewsDate.day(Date()))")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A compact title for navigation bars: the mark plus the publication name.
struct CompactMasthead: View {
    @ScaledMetric(relativeTo: .headline) private var height: CGFloat = 22

    var body: some View {
        HStack(spacing: 8) {
            HCGMark(height: min(height, 34))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text("News")
                .font(Typography.headline(.headline))
                .foregroundStyle(Palette.primaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HCG News")
    }
}

/// "A Hakmi Capital Group publication", with the corporate mark.
struct PublisherAttribution: View {
    var large = false

    var body: some View {
        VStack(spacing: 10) {
            Image(large ? "HCGLogo" : "HCGLogoTrimmed")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: large ? 180 : 110)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: large ? 18 : 8, style: .continuous))
                .accessibilityHidden(true)
            Text("A Hakmi Capital Group publication")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A Hakmi Capital Group publication")
    }
}
