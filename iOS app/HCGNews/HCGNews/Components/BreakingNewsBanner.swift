import SwiftUI
import Accessibility
import NewsCore
import NewsAppModel

/// One breaking headline at a time, only from articles the publication explicitly
/// flags as breaking. Manual previous / next; no auto-scrolling marquee. Changes are
/// instant under Reduce Motion.
struct BreakingNewsBanner: View {
    @Binding var carousel: BreakingCarousel
    let open: (ArticleSummary) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let current = carousel.current {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text((current.breaking?.label ?? "Breaking").uppercased())
                        .font(.system(.caption, weight: .heavy))
                        .tracking(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(Palette.onAccent)
                        .background(Palette.accent, in: Capsule())
                    if carousel.hasMultiple {
                        Text(carousel.positionLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Palette.secondaryText)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                    if carousel.hasMultiple && !typeSize.isAccessibilitySize { controls }
                }
                Button { open(current) } label: {
                    Text(current.headline)
                        .font(Typography.headline(.title3))
                        .foregroundStyle(Palette.primaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .id(current.id)
                .transition(reduceMotion ? .identity : .opacity)
                .accessibilityLabel("Breaking: \(current.headline)")
                .accessibilityHint(carousel.hasMultiple ? "Item \(carousel.positionLabel). Opens the article." : "Opens the article.")
                if carousel.hasMultiple && typeSize.isAccessibilitySize { controls }
            }
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle().fill(Palette.accent).frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5)).accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Breaking news")
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button { step(forward: false) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Previous breaking headline")
            Button { step(forward: true) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Next breaking headline")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.accent)
    }

    private func step(forward: Bool) {
        let change = { forward ? carousel.next() : carousel.previous() }
        if reduceMotion { change() } else { withAnimation(.easeInOut(duration: 0.25)) { change() } }
        if let headline = carousel.current?.headline {
            AccessibilityNotification.Announcement("Breaking: \(headline)").post()
        }
    }
}
