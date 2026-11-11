import Foundation
import NewsCore

/// A reader-facing explanation of a failure. No technical detail that could
/// leak data; no invented reassurance.
public struct UserFacingError: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case notConfigured, offline, notFound, restricted, forbidden, rateLimited, unavailable, contract, other
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
            self.init(.notConfigured, "Live publication not connected",
                      "This build is not yet connected to the HCG News publication. It shows no articles until HCG confirms the supported content API.",
                      "antenna.radiowaves.left.and.right.slash", retry: false)
        case .offline:
            self.init(.offline, "You're offline",
                      "HCG News couldn't reach the publication. Check your connection and try again.",
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
                      "HCG News marks this article as available to authorised HCG accounts only.",
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
