import Foundation

/// One sign-in attempt: unpredictable `state` and `nonce`, and a PKCE pair.
public struct AuthorizationAttempt: Sendable, Equatable {
    public let state: String
    public let nonce: String
    public let pkce: PKCEPair
    public let url: URL

    public init(configuration: ConnectConfiguration,
                state: String = PKCE.randomString(length: 43),
                nonce: String = PKCE.randomString(length: 43),
                pkce: PKCEPair = PKCE.makePair()) {
        self.state = state
        self.nonce = nonce
        self.pkce = pkce
        var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items += [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ]
        components.queryItems = items
        self.url = components.url!
    }
}

public enum CallbackError: Error, Equatable, Sendable {
    /// The redirect did not come back to this client's registered redirect URI.
    case unexpectedRedirect
    /// `state` missing or different: possible CSRF / mix-up. The code is discarded.
    case stateMismatch
    /// The user or the provider declined (`access_denied`).
    case accessDenied(String?)
    /// Any other OAuth error the provider returned.
    case providerError(code: String, description: String?)
    case missingCode
}

public enum AuthorizationCallback {
    /// Validates the redirect and returns the authorization code.
    /// Order matters: the redirect target and `state` are checked before anything else
    /// in the URL is trusted.
    public static func code(from callback: URL, attempt: AuthorizationAttempt, configuration: ConnectConfiguration) throws -> String {
        let expected = configuration.redirectURI
        guard callback.scheme?.lowercased() == expected.scheme?.lowercased(),
              (callback.host ?? "") == (expected.host ?? ""),
              normalisedPath(callback) == normalisedPath(expected)
        else { throw CallbackError.unexpectedRedirect }

        // Parameters can arrive in the query or (for some providers) the fragment.
        var items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let fragment = callback.fragment, var fc = URLComponents(string: "x:/") {
            fc.percentEncodedQuery = fragment
            items += fc.queryItems ?? []
        }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard let state = value("state"), state == attempt.state else { throw CallbackError.stateMismatch }
        if let error = value("error") {
            if error == "access_denied" { throw CallbackError.accessDenied(value("error_description")) }
            throw CallbackError.providerError(code: error, description: value("error_description"))
        }
        guard let code = value("code"), !code.isEmpty else { throw CallbackError.missingCode }
        return code
    }

    private static func normalisedPath(_ url: URL) -> String {
        let path = url.path
        return path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
    }
}
