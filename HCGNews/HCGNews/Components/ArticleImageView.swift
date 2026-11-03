import SwiftUI
import UIKit
import NewsCore

/// Loads and caches article images. HTTPS only (enforced upstream as well);
/// large images are downsampled to keep memory bounded.
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

    func load(_ url: URL, maxPixel: CGFloat = 2400) async -> UIImage? {
        if let hit = cached(url) { return hit }
        guard url.scheme?.lowercased() == "https" else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else { return nil }
            let longest = max(image.size.width * image.scale, image.size.height * image.scale)
            var final = image
            if longest > maxPixel {
                let factor = maxPixel / longest
                let target = CGSize(width: image.size.width * image.scale * factor,
                                    height: image.size.height * image.scale * factor)
                final = image.preparingThumbnail(of: target) ?? image
            }
            cache.setObject(final, forKey: url as NSURL, cost: Int(final.size.width * final.size.height * final.scale * final.scale * 4))
            return final
        } catch {
            return nil
        }
    }
}

/// An article image at its true proportions. Never cropped, never overlaid
/// with text (editorial artwork may contain its own headline text). When the
/// image is missing or fails, the view collapses instead of leaving an empty box.
struct ArticleImageView: View {
    let image: ArticleImage
    /// Upper bound for the displayed height (used for list thumbnails); nil for full width.
    var maxHeight: CGFloat?
    var cornerRadius: CGFloat = 6

    @Environment(\.palette) private var palette
    @State private var loaded: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let loaded {
                Image(uiImage: loaded)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .accessibilityLabel(image.alt ?? "")
                    .accessibilityHidden(image.alt == nil)
            } else if !failed {
                // Placeholder reserves the real aspect ratio only when the backend supplied it.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.surface)
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
            let result = await ImagePipeline.shared.load(image.url)
            loaded = result
            failed = result == nil
        }
    }
}

/// A figure: image plus caption and credit, as separate live text.
struct ArticleFigure: View {
    let image: ArticleImage
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArticleImageView(image: image)
            if image.caption != nil || image.credit != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let caption = image.caption {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                    if let credit = image.credit {
                        Text(credit)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText.opacity(0.9))
                            .accessibilityLabel("Credit: \(credit)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
