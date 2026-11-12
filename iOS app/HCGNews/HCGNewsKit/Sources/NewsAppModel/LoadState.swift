import Foundation
import NewsCore

/// A reader-facing explanation of a failure. Each kind is a distinct state with
/// its own wording and action; nothing is replaced by sample content.
public struct UserFacingError: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// No publication configuration installed.
        case notConfigured
        /// A configuration is installed but invalid.
        case invalidConfiguration
        case offline
        case notFound
        /// Backend marks the content as requiring an authorised HCG account.
        case restricted
        /// Signed in, but HCG or the service refused.
        case forbidden
        case rateLimited
        /// The service failed or is unavailable.
        case unavailable
        /// The response did not match the agreed contract.
        case contract
        case other
    }

    public let kind: Kind
    public let title: String
    public let message: String
    public let systemImage: String
    public let canRetry: Bool

    public init(_ error: Error) {
        let serviceError = error as? NewsServiceError ?? .other(String(describing: type(of: error)))
        switch serviceError {
        case .notConfigured:
            self.init(.notConfigured, "Publication not connected",
                      "This copy of HCG News has no publication connection set up, so it shows no articles. A connection can be added under Settings › Advanced.",
                      "antenna.radiowaves.left.and.right.slash", retry: false)
        case .invalidConfiguration:
            self.init(.invalidConfiguration, "Publication settings need attention",
                      "The installed publication configuration can't be used. Review it under Settings › Advanced, or remove it to return to the built-in settings.",
                      "exclamationmark.triangle", retry: false)
        case .offline:
            self.init(.offline, "You're offline",
                      "HCG News couldn't reach the publication. Downloaded articles are still available in Saved.",
                      "wifi.slash", retry: true)
        case .timedOut:
            self.init(.offline, "The publication is taking too long",
                      "The request timed out. Try again in a moment.", "hourglass", retry: true)
        case .notFound:
            self.init(.notFound, "Article not available",
                      "This article could not be found. It may have been unpublished or moved.",
                      "doc.questionmark", retry: false)
        case .restricted:
            self.init(.restricted, "Sign-in required",
                      "The publication marks this article as available to authorised HCG accounts only.",
                      "lock", retry: false)
        case .forbidden:
            self.init(.forbidden, "No access",
                      "Your HCG account does not have access to this content. Access is managed centrally by HCG.",
                      "lock.slash", retry: false)
        case .rateLimited:
            self.init(.rateLimited, "Too many requests",
                      "The publication asked the app to slow down. Try again in about a minute.",
                      "clock", retry: true)
        case .unavailable, .server:
            self.init(.unavailable, "Publication unavailable",
                      "The HCG News service is not responding right now. Try again later.",
                      "exclamationmark.icloud", retry: true)
        case .contractMismatch, .unsupportedContractVersion:
            self.init(.contract, "This version can't read the publication",
                      "The publication's data did not match what this version of the app expects. An app update may be required.",
                      "exclamationmark.triangle", retry: true)
        case .noPublicContent:
            self.init(.unavailable, "Connected, but no articles are readable",
                      "The publication answered, but returned no published articles to the app. If articles are live on news.hakmicapitalgroup.com, public reading for apps isn't enabled yet. Run the access check described in the integration report.",
                      "eye.slash", retry: true)
        case .other:
            self.init(.other, "Something went wrong",
                      "The content could not be loaded. Try again.", "exclamationmark.triangle", retry: true)
        }
    }

    private init(_ kind: Kind, _ title: String, _ message: String, _ systemImage: String, retry: Bool) {
        self.kind = kind
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.canRetry = retry
    }

    /// True for states caused by configuration rather than the network or server.
    public var isConfigurationProblem: Bool { kind == .notConfigured || kind == .invalidConfiguration }
}

public enum LoadState<Value: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(UserFacingError)

    public var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
