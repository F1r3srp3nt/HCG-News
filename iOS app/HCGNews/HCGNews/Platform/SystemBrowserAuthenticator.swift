import AuthenticationServices
import UIKit
import HCGConnect

/// HCG Connect sign-in through the system authentication browser
/// (`ASWebAuthenticationSession`), as RFC 8252 recommends for native apps.
/// Never an embedded web view; the app cannot see what the user types.
///
/// It only returns the callback URL. State validation, PKCE and the token exchange
/// happen in `HCGConnectCoordinator`.
struct SystemBrowserAuthenticator: BrowserAuthenticating {
    func authenticate(url: URL, callbackScheme: String, ephemeral: Bool) async throws -> URL {
        let runner = await Runner()
        return try await runner.run(url: url, callbackScheme: callbackScheme, ephemeral: ephemeral)
    }
}

@MainActor
private final class Runner: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?

    func run(url: URL, callbackScheme: String, ephemeral: Bool) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                MainActor.assumeIsolated {
                    if let callbackURL {
                        self?.finish(.success(callbackURL))
                    } else if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                        self?.finish(.failure(BrowserAuthenticationError.cancelled))
                    } else if let error {
                        self?.finish(.failure(BrowserAuthenticationError.unavailable((error as NSError).domain)))
                    } else {
                        self?.finish(.failure(BrowserAuthenticationError.cancelled))
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = ephemeral
            self.session = session
            if !session.start() {
                finish(.failure(BrowserAuthenticationError.unavailable("start failed")))
            }
        }
    }

    /// Resumes the continuation exactly once, whichever path finishes first
    /// (start() failing and the completion handler can both report an error).
    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session = nil
        continuation.resume(with: result)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            return active?.windows.first(where: \.isKeyWindow) ?? active?.windows.first ?? ASPresentationAnchor()
        }
    }
}
