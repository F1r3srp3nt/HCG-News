import SwiftUI
import NewsAppModel

/// Full-width state for failures and empty content.
struct MessageStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var details: [String] = []
    var retry: (() async -> Void)?
    var action: (title: String, run: () -> Void)?

    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(.largeTitle))
                .foregroundStyle(Palette.silver)
                .accessibilityHidden(true)
            Text(title)
                .font(Typography.headline(.title3))
                .foregroundStyle(Palette.primaryText)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !details.isEmpty {
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(details, id: \.self) { detail in
                            Text("• " + detail)
                                .font(.footnote)
                                .foregroundStyle(Palette.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.footnote)
                .frame(maxWidth: 480)
            }
            HStack(spacing: 12) {
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
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isRetrying)
                }
                if let action {
                    Button(action.title, action: action.run).buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

extension MessageStateView {
    init(error: UserFacingError, details: [String] = [], retry: (() async -> Void)?, action: (title: String, run: () -> Void)? = nil) {
        self.init(title: error.title, message: error.message, systemImage: error.systemImage,
                  details: details, retry: error.canRetry ? retry : nil, action: action)
    }
}

/// The publication state for configuration problems, with a route to Advanced settings
/// and a plain link to the website. The app never scrapes the website.
struct ConfigurationStateView: View {
    let error: UserFacingError
    let problems: [String]
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            MessageStateView(error: error, details: problems, retry: nil,
                             action: ("Open Advanced Settings", { router.showAdvancedSettings() }))
            Link(destination: URL(string: "https://news.hakmicapitalgroup.com")!) {
                Label("Read HCG News on the web", systemImage: "safari")
            }
            .font(.footnote.weight(.semibold))
            Text("Downloaded articles stay readable in Saved.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(.vertical, 24)
    }
}

/// Picks the right state view for any publication error.
struct PublicationErrorView: View {
    let error: UserFacingError
    let problems: [String]
    let retry: () async -> Void

    var body: some View {
        if error.isConfigurationProblem {
            ConfigurationStateView(error: error, problems: problems)
        } else {
            MessageStateView(error: error, retry: retry)
        }
    }
}

struct LoadingStateView: View {
    var label = "Loading"
    var body: some View {
        ProgressView(label)
            .frame(maxWidth: .infinity, minHeight: 200)
    }
}

/// Inline notice under already-loaded content (e.g. a failed refresh or "load more").
struct InlineErrorRow: View {
    let error: UserFacingError
    let retry: () async -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: error.systemImage).foregroundStyle(Palette.warning).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(error.title).font(.subheadline.weight(.semibold))
                Text("Showing what was loaded earlier. " + error.message).font(.footnote).foregroundStyle(Palette.secondaryText)
                if error.canRetry {
                    Button("Try Again") { Task { await retry() } }
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
        }
        .foregroundStyle(Palette.primaryText)
        .cardSurface(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }
}

/// A small status capsule (cyan only for "good / in progress" status).
struct StatusBadge: View {
    enum Tone { case neutral, good, attention, problem }
    let text: String
    var tone: Tone = .neutral
    var systemImage: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
    }

    private var color: Color {
        switch tone {
        case .neutral: Palette.silver
        case .good: Palette.accent
        case .attention: Palette.warning
        case .problem: Palette.destructive
        }
    }
}
