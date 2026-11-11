import SwiftUI

/// The supplied HCG logo (silver mark on black), shown on its native black ground.
/// `HCGLogoTrimmed` is the same artwork with the empty margins cropped for small sizes.
struct BrandMark: View {
    var height: CGFloat = 28

    var body: some View {
        Image("HCGLogoTrimmed")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: height * 0.12, style: .continuous))
            .accessibilityLabel("Hakmi Capital Group")
    }
}

/// Logo plus the publication name, for the Home navigation bar.
struct MastheadTitle: View {
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .headline) private var logoHeight: CGFloat = 26

    var body: some View {
        HStack(spacing: 8) {
            BrandMark(height: min(logoHeight, 40))
            Text("HCG News")
                .font(Typography.headline(.headline))
                .foregroundStyle(palette.primaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HCG News")
        .accessibilityAddTraits(.isHeader)
    }
}
