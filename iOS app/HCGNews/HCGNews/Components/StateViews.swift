import SwiftUI
import NewsAppModel

/// Full-screen state for loading failures, not-connected and empty content.
struct MessageStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var details: [String] = []
    var retry: (() async -> Void)?

    @Environment(\.palette) private var palette
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(.largeTitle))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(Typography.headline(.title3))
                .foregroundStyle(palette.primaryText)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
            if !details.isEmpty {
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(details, id: \.self) { detail in
                            Text("• " + detail)
                                .font(.footnote)
                                .foregroundStyle(palette.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.footnote)
                .frame(maxWidth: 480)
            }
            if let retry {
                Button {
                    Task {
                        isRetrying = true
                        await retry()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying { ProgressView() } else { Text("Try Again") }
                }
                .buttonStyle(.bordered)
                .disabled(isRetrying)
            }
        }
        .padding(24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

extension MessageStateView {
    init(error: UserFacingError, details: [String] = [], retry: (() async -> Void)?) {
        self.init(title: error.title, message: error.message, systemImage: error.systemImage,
                  details: details, retry: error.canRetry ? retry : nil)
    }
}

/// Shown instead of content when no supported publication API is configured.
/// Offers the public website as a plain link; the app does not scrape it.
struct NotConnectedView: View {
    let problems: [String]
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 18) {
            MessageStateView(
                title: "Live publication not connected",
                message: "This development build of HCG News is not yet connected to the publication's content service, so it shows no articles. Nothing here is live reporting.",
                systemImage: "antenna.radiowaves.left.and.right.slash",
                details: problems)
            Link(destination: URL(string: "https://news.hakmicapitalgroup.com")!) {
                Label("Read HCG News on the web", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(palette.onAccent)
        }
        .padding(.vertical, 24)
    }
}

struct LoadingStateView: View {
    var label = "Loading"
    var body: some View {
        ProgressView(label)
            .frame(maxWidth: .infinity, minHeight: 200)
    }
}

/// Inline error under already-loaded content (e.g. a failed "load more").
struct InlineErrorRow: View {
    let error: UserFacingError
    let retry: () async -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: error.systemImage).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(error.title).font(.subheadline.weight(.semibold))
                Text(error.message).font(.footnote).foregroundStyle(palette.secondaryText)
                if error.canRetry {
                    Button("Try Again") { Task { await retry() } }
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .foregroundStyle(palette.primaryText)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
