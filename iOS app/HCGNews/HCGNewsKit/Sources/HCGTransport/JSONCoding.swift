import Foundation

/// Shared JSON handling for HCG services.
public enum HCGJSON {
    /// A decoder that accepts ISO 8601 timestamps with or without fractional
    /// seconds, and with `Z` or a numeric offset. Anything else fails decoding
    /// rather than being silently replaced by "now".
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parseDate(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised date format")
            }
            return date
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatDate(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: trimmed) { return date }
        // Postgres timestamptz with microseconds ("…T10:15:00.123456+00:00"): keep milliseconds.
        if let dot = trimmed.firstIndex(of: "."), trimmed.distance(from: trimmed.startIndex, to: dot) >= 19 {
            let fractionStart = trimmed.index(after: dot)
            let digits = trimmed[fractionStart...].prefix(while: { $0.isNumber })
            if digits.count > 3 {
                let rest = trimmed[digits.endIndex...]
                let normalised = String(trimmed[..<fractionStart]) + digits.prefix(3) + rest
                if let date = parseDate(normalised) { return date }
            }
        }
        // Postgres-style "2026-11-03 10:15:00+00" / "+00:00" (space separator).
        if trimmed.count > 10, trimmed[trimmed.index(trimmed.startIndex, offsetBy: 10)] == " " {
            var normalised = trimmed
            normalised.replaceSubrange(
                normalised.index(normalised.startIndex, offsetBy: 10)...normalised.index(normalised.startIndex, offsetBy: 10),
                with: "T")
            if normalised.hasSuffix("+00") { normalised += ":00" }
            if let date = withFraction.date(from: normalised) ?? plain.date(from: normalised) { return date }
        }
        return nil
    }

    public static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// Guards configuration files against containing credentials that must never
/// ship in a native app (client secrets, service-role keys, passwords).
public enum SecretGuard {
    /// Key names that indicate a confidential credential.
    public static let forbiddenKeyFragments = [
        "secret", "password", "passwd", "service_role", "servicerole", "private_key", "privatekey",
    ]

    /// Returns the offending key paths found anywhere in a JSON object.
    public static func forbiddenKeys(inJSON data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var found: [String] = []
        walk(object, path: "", into: &found)
        return found.sorted()
    }

    private static func walk(_ value: Any, path: String, into found: inout [String]) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                let lowered = key.lowercased()
                if forbiddenKeyFragments.contains(where: { lowered.contains($0) }) {
                    found.append(childPath)
                }
                walk(child, path: childPath, into: &found)
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                walk(child, path: "\(path)[\(index)]", into: &found)
            }
        }
    }

    /// If `token` is a JWT, returns its `role` claim (unverified; used only to
    /// refuse obviously privileged keys such as a Supabase `service_role` key).
    public static func jwtRoleClaim(_ token: String) -> String? {
        jwtClaims(token)?["role"] as? String
    }

    /// The (unverified) claims of a JWT, or nil if `token` is not a JWT.
    public static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}

/// Hosts the HCG News app is allowed to talk to for content and identity.
/// Configuration pointing anywhere else is rejected.
public enum HCGHostPolicy {
    public static let apexDomain = "hakmicapitalgroup.com"

    public static func isHCGHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == apexDomain || host.hasSuffix("." + apexDomain)
    }

    /// HTTPS and an HCG host. Used for configuration and canonical article URLs.
    public static func isTrustedHCGURL(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https" else { return false }
        return isHCGHost(url.host)
    }
}
