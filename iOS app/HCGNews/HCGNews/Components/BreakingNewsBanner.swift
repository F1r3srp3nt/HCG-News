import SwiftUI
import Accessibility
import NewsCore
import NewsAppModel

/// One breaking headline at a time, chosen only from articles the backend
/// explicitly flags as breaking. Navigation is manual (previous / next);
/// there is no auto-scrolling marquee. Transitions are removed under Reduce Motion.
struct BreakingNewsBanner: View {
    @Binding var carousel: BreakingCarousel
    let open: (ArticleSummary) -> Void

    @Environment(\.palette) private var palette
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
                        .foregroundStyle(palette.onAccent)
                        .background(palette.accent, in: Capsule())
                    if carousel.hasMultiple {
                        Text(carousel.positionLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.secondaryText)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                    if carousel.hasMultiple && !typeSize.isAccessibilitySize {
                        controls
                    }
                }

                Button { open(current) } label: {
                    Text(current.headline)
                        .font(Typography.headline(.title3))
                        .foregroundStyle(palette.primaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .id(current.id)
                .transition(reduceMotion ? .identity : .opacity)
                .accessibilityLabel("Breaking: \(current.headline)")
                .accessibilityHint(carousel.hasMultiple ? "Item \(carousel.positionLabel). Opens the article." : "Opens the article.")

                if carousel.hasMultiple && typeSize.isAccessibilitySize {
                    controls
                }
            }
            .padding(14)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.accent.opacity(0.45), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Breaking news")
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button { step(forward: false) } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Previous breaking headline")
            Button { step(forward: true) } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Next breaking headline")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.accent)
    }

    private func step(forward: Bool) {
        let change = { forward ? carousel.next() : carousel.previous() }
        if reduceMotion {
            change()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { change() }
        }
        if let headline = carousel.current?.headline {
            AccessibilityNotification.Announcement("Breaking: \(headline)").post()
        }
    }
}
