import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The single network seam used by every HCG News service.
///
/// Tests inject a fake transport; the app uses `URLSessionTransport`.
/// Implementations must never log request headers or bodies (they can carry
/// bearer tokens or authorization codes).
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Transport-level failures, normalised so callers can present honest states.
public enum TransportError: Error, Equatable, Sendable {
    /// The device is offline or the host could not be reached.
    case offline
    /// The request timed out.
    case timedOut
    /// TLS / certificate failure. Never bypassed.
    case insecureConnection
    /// The response was not an HTTP response.
    case invalidResponse
    /// Any other transport failure (description is safe to show; it contains no secrets).
    case other(String)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.makeDefaultSession()) {
        self.session = session
    }

    /// An ephemeral session: no shared cookie jar, no persistent URL cache of
    /// authenticated responses. Public article images use their own cache in the UI.
    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        #if !canImport(FoundationNetworking)
        configuration.waitsForConnectivity = false
        #endif
        return URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await dataTask(request)
            guard let http = response as? HTTPURLResponse else { throw TransportError.invalidResponse }
            return (data, http)
        } catch let error as TransportError {
            throw error
        } catch let error as URLError {
            throw Self.map(error)
        } catch {
            throw TransportError.other(String(describing: type(of: error)))
        }
    }

    private func dataTask(_ request: URLRequest) async throws -> (Data, URLResponse) {
        #if canImport(FoundationNetworking)
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: (data ?? Data(), response))
                } else {
                    continuation.resume(throwing: TransportError.invalidResponse)
                }
            }
            task.resume()
        }
        #else
        return try await session.data(for: request)
        #endif
    }

    static func map(_ error: URLError) -> TransportError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timedOut
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            return .insecureConnection
        default:
            return .other("URLError \(error.code.rawValue)")
        }
    }
}
