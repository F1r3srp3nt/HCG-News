import SwiftUI
import UIKit
import NewsCore

/// Resolves a remote image to a local file from the offline library (if downloaded).
struct OfflineImageResolver: Sendable {
    let resolve: @Sendable (URL) async -> URL?
    static let none = OfflineImageResolver { _ in nil }
}

private struct OfflineImageResolverKey: EnvironmentKey {
    static let defaultValue = OfflineImageResolver.none
}

extension EnvironmentValues {
    var offlineImageResolver: OfflineImageResolver {
        get { self[OfflineImageResolverKey.self] }
        set { self[OfflineImageResolverKey.self] = newValue }
    }
}

/// Loads and caches images. Remote images must be HTTPS. Local files are only
/// read from the app's own container (offline downloads and draft media).
@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 150 * 1024 * 1024)
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL, localFallback: URL?) async -> UIImage? {
        if let hit = cached(url) { return hit }
        var data: Data?
        if url.isFileURL, Self.isInsideContainer(url) {
            data = try? Data(contentsOf: url)
        } else if url.scheme?.lowercased() == "https" {
            if let (remote, response) = try? await session.data(from: url),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                data = remote
            }
        }
        if data == nil, let localFallback, Self.isInsideContainer(localFallback) {
            data = try? Data(contentsOf: localFallback)
        }
        guard let data, var image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height) * image.scale
        if longest > 2400 {
            let factor = 2400 / longest
            image = image.preparingThumbnail(of: CGSize(width: image.size.width * image.scale * factor,
                                                        height: image.size.height * image.scale * factor)) ?? image
        }
        cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }

    static func isInsideContainer(_ url: URL) -> Bool {
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        return url.standardizedFileURL.path.hasPrefix(home)
    }
}

/// An image at its true proportions: never cropped, never overlaid with text
/// (editorial artwork may contain its own headline). A missing image collapses
/// rather than leaving an empty box. Tapping enlarges it when `zoomable`.
/// The website's "no featured image" tile: "HCG News" in italic serif over a quiet
/// signal-tinted surface, with the section eyebrow.
struct MediaPlaceholder: View {
    var section: String?

    var body: some View {
        ZStack {
            Palette.surface
            RadialGradient(colors: [Palette.accent.opacity(0.12), .clear], center: UnitPoint(x: 0.7, y: 0.3),
                           startRadius: 0, endRadius: 220)
            VStack(spacing: 6) {
                Text("HCG News").font(Typography.serifItalic(.title3)).foregroundStyle(Palette.silver)
                if let section {
                    Text(section.uppercased()).font(Typography.sans(.caption2, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.map { "HCG News, \($0). No featured image" } ?? "HCG News. No featured image")
    }
}

struct ArticleImageView: View {
    let image: ArticleImage
    var maxHeight: CGFloat?
    var cornerRadius: CGFloat = 6
    var zoomable = false
    /// When set, the image fills a frame of this width ÷ height (cropped, like the
    /// website's 16:10 card media). Otherwise it is shown whole at its own proportions.
    var fillAspect: CGFloat? = nil
    /// Section name for the placeholder when a fill-frame image is missing.
    var placeholderSection: String? = nil

    @Environment(\.offlineImageResolver) private var resolver
    @State private var loaded: UIImage?
    @State private var failed = false
    @State private var showingViewer = false

    var body: some View {
        Group {
            if let fillAspect {
                Color.clear
                    .aspectRatio(fillAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if let loaded {
                            Image(uiImage: loaded).resizable().aspectRatio(contentMode: .fill)
                        } else if failed {
                            MediaPlaceholder(section: placeholderSection)
                        } else {
                            Palette.surface
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .accessibilityElement()
                    .accessibilityLabel(image.alt ?? "")
                    .accessibilityHidden(image.alt == nil || loaded == nil)
            } else if let loaded {
                let picture = Image(uiImage: loaded)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                if zoomable {
                    Button { showingViewer = true } label: { picture }
                        .buttonStyle(.plain)
                        .accessibilityLabel(image.alt ?? "Image")
                        .accessibilityHint("Opens the image full screen")
                        .fullScreenCover(isPresented: $showingViewer) {
                            PhotoViewer(image: loaded, meta: image)
                        }
                } else {
                    picture
                        .accessibilityLabel(image.alt ?? "")
                        .accessibilityHidden(image.alt == nil)
                }
            } else if !failed {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.surface)
                    .aspectRatio(CGFloat(image.aspectRatio ?? 16.0 / 9.0), contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: maxHeight)
                    .accessibilityHidden(true)
            }
        }
        .task(id: image.url) {
            if let hit = ImagePipeline.shared.cached(image.url) {
                loaded = hit
                return
            }
            failed = false
            let local = await resolver.resolve(image.url)
            let result = await ImagePipeline.shared.load(image.url, localFallback: local)
            loaded = result
            failed = result == nil
        }
    }
}

/// Image with caption and credit as separate live text.
struct ArticleFigure: View {
    let image: ArticleImage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArticleImageView(image: image, zoomable: true)
            if image.caption != nil || image.credit != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let caption = image.caption {
                        Text(caption).font(.footnote).foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let credit = image.credit {
                        Text(credit)
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Credit: \(credit)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Full-screen photo with pinch and double-tap zoom, caption and an explicit Close button.
struct PhotoViewer: View {
    let image: UIImage
    let meta: ArticleImage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale * pinch)
                    .frame(minWidth: 0, minHeight: 0)
                    .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in scale = min(max(scale * value.magnification, 1), 4) })
                    .onTapGesture(count: 2) {
                        if reduceMotion { scale = scale > 1 ? 1 : 2 } else { withAnimation(.easeInOut(duration: 0.2)) { scale = scale > 1 ? 1 : 2 } }
                    }
                    .accessibilityLabel(meta.alt ?? "Image")
                    .accessibilityAddTraits(.isImage)
            }
            .defaultScrollAnchor(.center)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Close")
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            if meta.caption != nil || meta.credit != nil {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        if let caption = meta.caption { Text(caption).font(.footnote) }
                        if let credit = meta.credit { Text(credit).font(.caption).opacity(0.8) }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.black.opacity(0.6))
                }
            }
        }
        .accessibilityAction(named: "Zoom in") { scale = min(scale + 1, 4) }
        .accessibilityAction(named: "Zoom out") { scale = max(scale - 1, 1) }
    }
}
