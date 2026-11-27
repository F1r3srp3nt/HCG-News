import SwiftUI
import Accessibility
import NewsCore
import NewsAppModel

/// The website's breaking-news ticker: a red bar with "BREAKING" and one headline at a
/// time, only from articles the publication explicitly flags as breaking.
///
/// With several breaking stories it advances every 7 seconds, like the website, except
/// when Reduce Motion or VoiceOver is on, or the reader paused it. Pause/Play and Next are
/// always available (WCAG 2.2.2), and changes are announced politely to VoiceOver users only
/// when they step through manually.
struct BreakingNewsBanner: View {
    @Binding var carousel: BreakingCarousel
    let open: (ArticleSummary) -> Void

    static let interval: Duration = .seconds(7)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var paused = false

    private var autoAdvances: Bool { carousel.hasMultiple && !paused && !reduceMotion && !voiceOver }

    var body: some View {
        if let current = carousel.current {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                Text((current.breaking?.label ?? "Breaking").uppercased())
                    .font(Typography.sans(.caption, weight: .bold))
                    .tracking(0.4)
                    .fixedSize()
                    .accessibilityHidden(true)
                Button { open(current) } label: {
                    Text(current.headline)
                        .font(Typography.sans(.subheadline, weight: .medium))
                        .multilineTextAlignment(.leading)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .id(current.id)
                .transition(reduceMotion ? .identity : .opacity)
                .accessibilityLabel("Breaking: \(current.headline)")
                .accessibilityHint(carousel.hasMultiple ? "\(carousel.positionLabel). Opens the article." : "Opens the article.")
                if carousel.hasMultiple { controls }
            }
            .foregroundStyle(Palette.onBreaking)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.breaking)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Breaking news")
            .task(id: TickerKey(id: current.id, running: autoAdvances)) {
                guard autoAdvances else { return }
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) { carousel.next() }
            }
        }
    }

    private struct TickerKey: Equatable { let id: ArticleID; let running: Bool }

    private var controls: some View {
        HStack(spacing: 0) {
            if !reduceMotion && !voiceOver {
                Button { paused.toggle() } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(paused ? "Resume breaking headlines" : "Pause breaking headlines")
            }
            Button { step() } label: {
                Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Next breaking headline")
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.borderless)
    }

    private func step() {
        if reduceMotion { carousel.next() } else { withAnimation(.easeInOut(duration: 0.25)) { carousel.next() } }
        if let headline = carousel.current?.headline {
            AccessibilityNotification.Announcement("Breaking: \(headline)").post()
        }
    }
}
