import Foundation
import CryptoKit
import Security

/// Configuration for DupeFinder Pro's Polar.sh product.
///
/// DupeFinder Pro is a SEPARATE product from MacGroom Pro — per-app
/// licensing, not a bundle — so it needs its own Polar organization (or at
/// minimum its own product within one), independent of MacGroom's.
///
/// TODO(polar-setup): none of this exists yet. Before shipping Pro gating
/// for real:
///   1. Create a "DupeFinder Pro" product in Polar.sh (either a new
///      organization, or a new product inside the existing gogenops
///      organization — decide deliberately, see the warning below).
///   2. Enable that product's License Keys benefit.
///   3. Copy the organization's ID from Polar's dashboard and paste it
///      below as `organizationId` (replacing the placeholder).
///   4. Point "Unlock Pro" buttons at that product's real checkout URL —
///      `purchaseURL` below is a placeholder.
///   5. Optionally set env var DUPEFINDER_POLAR_ORG_ID to override
///      `organizationId` at build/run time (useful for testing against a
///      sandbox org before the real one is public).
///
/// ⚠️ Known limitation, read before reusing MacGroom's existing
/// organization ID here: Polar's `/v1/customer-portal/license-keys/validate`
/// endpoint validates a key against an *organization*, not a specific
/// product within it — the response this app decodes (see `License`)
/// carries no product/benefit identifier to cross-check. If DupeFinder Pro
/// is created as a second product inside MacGroom's existing gogenops
/// organization, a valid MacGroom Pro license key would also validate here
/// and unlock DupeFinder Pro, and vice versa. That may be an acceptable,
/// deliberate choice (an implicit "gogenops Pro bundle") — but it must be
/// a decision made when filling in step 1 above, not a silent accident.
/// The placeholder organization ID below is intentionally invalid so Pro
/// stays locked (fails closed) until someone makes that call.
enum PolarConfig {
    /// Polar's organization ID for DupeFinder Pro's Polar org. Placeholder
    /// until the TODO above is done — a request with this value 404s from
    /// Polar, so every license check fails closed rather than silently
    /// trusting an unrelated org.
    static var organizationId: String {
        ProcessInfo.processInfo.environment["DUPEFINDER_POLAR_ORG_ID"]
            ?? "TODO-REPLACE-WITH-DUPEFINDER-POLAR-ORGANIZATION-ID"
    }

    /// True once `organizationId` has been replaced with a real Polar org
    /// id. While this is false, `LicenseChecker.verify` short-circuits
    /// before ever hitting the network — every request against the
    /// placeholder id 404s from Polar, which otherwise maps to "invalid
    /// license key," actively misleading a real purchaser who pastes a
    /// correct key into a build that shipped before step 1 above was done.
    static var isConfigured: Bool {
        !organizationId.hasPrefix("TODO-REPLACE")
    }

    /// Where "Unlock Pro" buttons should send the user. TODO: replace with
    /// the real Polar checkout URL once the product exists.
    static let purchaseURL = URL(string: "https://gogenops.com/mac-apps/dupefinder/#pro")!

    /// `@AppStorage` key for the stored license key — scoped to this app's
    /// own bundle id, distinct from MacGroom's
    /// `com.macgroom.disksweeper.licenseKey`.
    static let storedKeyDefaultsKey = "com.rajeshsood.dupefinder.licenseKey"
}

/// Local, tamper-evident cache for verified license state. Same design as
/// MacGroom's `SecureLicenseCache` (Keychain-backed, HMAC-tagged — not
/// plain `UserDefaults`, which a `defaults write` command could forge
/// outright): Keychain isn't readable/writable via `defaults`/`plutil`,
/// and a forged payload still fails the HMAC tag check on read and is
/// discarded, forcing a real network re-check.
///
/// **Honest limit, stated plainly** (same as MacGroom's): this raises the
/// bar from "one shell command" to "extract the embedded key from the
/// compiled binary, or run under a debugger and patch around the check" —
/// it doesn't eliminate offline bypass entirely, which no purely
/// client-side check can.
private enum SecureLicenseCache {
    private static let licenseService = "com.rajeshsood.dupefinder.license.cache.v1"

    /// Byte-masked so the secret doesn't sit in the binary's strings table
    /// as plain readable text. This is DupeFinder's own key, distinct from
    /// MacGroom's — do not reuse MacGroom's masked bytes here.
    private static var hmacKey: SymmetricKey {
        let masked: [UInt8] = [
            0x71, 0x2c, 0xa8, 0x0d, 0x5e, 0x9b, 0x33, 0x7f, 0xc4, 0x18,
            0x6a, 0xe2, 0x40, 0xb5, 0x97, 0x1e, 0xd8, 0x63, 0xf0, 0x25,
            0x4c, 0xa9, 0x7d, 0x11, 0x88
        ]
        let bytes = masked.enumerated().map { i, b in b ^ UInt8((i * 11 + 23) & 0xFF) }
        return SymmetricKey(data: Data(bytes))
    }

    private struct SignedPayload: Codable {
        let payload: Data
        let tag: Data
    }

    private struct CachedEnvelope: Codable {
        let cachedAt: Date
        let license: License
    }

    private static func computeTag(_ payload: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: payload, using: hmacKey))
    }

    static func readLicense(_ licenseKey: String) -> (Date, License)? {
        guard let data = keychainRead(service: licenseService, account: licenseKey) else { return nil }
        guard let signed = try? JSONDecoder().decode(SignedPayload.self, from: data) else { return nil }
        guard computeTag(signed.payload) == signed.tag else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(CachedEnvelope.self, from: signed.payload) else { return nil }
        return (envelope.cachedAt, envelope.license)
    }

    static func writeLicense(_ licenseKey: String, _ license: License) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(CachedEnvelope(cachedAt: Date(), license: license)) else { return }
        let signed = SignedPayload(payload: payload, tag: computeTag(payload))
        guard let signedData = try? JSONEncoder().encode(signed) else { return }
        keychainWrite(service: licenseService, account: licenseKey, data: signedData)
    }

    static func clearLicense(_ licenseKey: String) {
        keychainDelete(service: licenseService, account: licenseKey)
    }

    static func clearAll() {
        keychainDeleteAll(service: licenseService)
    }

    // MARK: - Keychain primitives

    private static func keychainRead(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func keychainWrite(service: String, account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func keychainDelete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func keychainDeleteAll(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Process-wide serialization for `LicenseChecker.verify()` calls, keyed by
/// license key — the main window and the (independent) Settings scene can
/// each own a `LicenseChecker`, so without this two concurrent `verify()`
/// calls for the same key would each independently hit the network.
private final class VerifyLock: @unchecked Sendable {
    static let shared = VerifyLock()

    private let lock = NSLock()
    private var inFlight: [String: Task<License, Error>] = [:]

    func run(key: String, _ operation: @escaping () async throws -> License) async throws -> License {
        let (task, isNew) = getOrCreate(key: key, operation: operation)
        defer { if isNew { clear(key) } }
        return try await task.value
    }

    private func getOrCreate(
        key: String,
        operation: @escaping () async throws -> License
    ) -> (task: Task<License, Error>, isNew: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = inFlight[key] {
            return (existing, false)
        }
        let task = Task { try await operation() }
        inFlight[key] = task
        return (task, true)
    }

    private func clear(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        inFlight[key] = nil
    }
}

/// Error types for license verification — same shape as MacGroom's.
public enum LicenseCheckError: LocalizedError {
    case invalidLicenseKey
    case networkError(URLError)
    case invalidResponse
    case licenseExpired
    case licenseDisabled
    case activationLimitExceeded
    case activationFailed(String)
    case codingError(Error)
    case unknown(String)
    case wrongProduct
    case notYetAvailable

    public var errorDescription: String? {
        switch self {
        case .invalidLicenseKey:
            return "The license key is invalid or not recognized."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from the license server."
        case .licenseExpired:
            return "This license has expired."
        case .licenseDisabled:
            return "This license has been disabled."
        case .activationLimitExceeded:
            return "This license has reached its activation limit."
        case .activationFailed(let message):
            return "Activation failed: \(message)"
        case .codingError(let error):
            return "Error processing license data: \(error.localizedDescription)"
        case .unknown(let message):
            return message
        case .wrongProduct:
            return "This license key isn't valid for DupeFinder."
        case .notYetAvailable:
            return "DupeFinder Pro isn't available for purchase yet. Please check back soon."
        }
    }
}

/// Represents a verified license. `instanceId` is always nil under the
/// Polar integration — see MacGroom's `License` doc comment.
public struct License: Codable, Equatable {
    public let key: String
    public let isValid: Bool
    public let status: String?
    public let expiresAt: Date?
    public let activationLimit: Int?
    public let activationUsage: Int?
    public let instanceId: String?

    public init(
        key: String,
        isValid: Bool,
        status: String? = nil,
        expiresAt: Date? = nil,
        activationLimit: Int? = nil,
        activationUsage: Int? = nil,
        instanceId: String? = nil
    ) {
        self.key = key
        self.isValid = isValid
        self.status = status
        self.expiresAt = expiresAt
        self.activationLimit = activationLimit
        self.activationUsage = activationUsage
        self.instanceId = instanceId
    }
}

/// Main license-checking service — template: MacGroom's `LicenseChecker`
/// in `mac-cleanup/Sources/MacGroomLicenseCheck.swift`. Uses Polar.sh's
/// customer-portal License Keys API
/// (`POST /v1/customer-portal/license-keys/validate`), which needs no
/// `Authorization` header — see that file's doc comment for the confirmed
/// request/response shape. `organizationId` here is DupeFinder's own (see
/// `PolarConfig`), not MacGroom's.
public class LicenseChecker {
    private let urlSession: URLSession

    public init(urlSession: URLSession = URLSession.shared) {
        self.urlSession = urlSession
    }

    /// Verify a license key against Polar.
    public func verify(
        licenseKey: String,
        useCache: Bool = true,
        cacheDuration: TimeInterval = 7 * 24 * 3600
    ) async throws -> License {
        // Fails closed but honestly: while the placeholder org id is still
        // in place, every request 404s from Polar and would otherwise map
        // to "invalid license key" — misleading a real purchaser who pastes
        // a correct key. Short-circuit before cache or network so the
        // message is accurate regardless of what's cached.
        guard PolarConfig.isConfigured else {
            throw LicenseCheckError.notYetAvailable
        }

        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespaces)

        return try await VerifyLock.shared.run(key: trimmedKey) { [self] in
            if useCache, let cached = self.getCachedLicense(trimmedKey) {
                if Date().timeIntervalSince(cached.0) < cacheDuration {
                    return cached.1
                } else {
                    self.clearCache(trimmedKey)
                }
            }

            let license = try await self.validateRemote(trimmedKey)
            self.setCachedLicense(trimmedKey, license)
            return license
        }
    }

    /// Clear cached license for a key
    public func clearCache(_ licenseKey: String) {
        SecureLicenseCache.clearLicense(licenseKey)
    }

    /// Clear all cached licenses
    public func clearAllCache() {
        SecureLicenseCache.clearAll()
    }

    // MARK: - Private Methods

    private func validateRemote(_ licenseKey: String) async throws -> License {
        var request = URLRequest(url: URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/validate")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "key": licenseKey,
            "organization_id": PolarConfig.organizationId
        ])

        let (data, httpResponse) = try await send(request)

        guard httpResponse.statusCode == 200 else {
            throw mapErrorResponse(status: httpResponse.statusCode, data: data)
        }

        struct PolarLicenseKeyResponse: Decodable {
            let key: String
            let status: String
            let limitActivations: Int?
            let usage: Int?
            let expiresAt: String?

            enum CodingKeys: String, CodingKey {
                case key, status, usage
                case limitActivations = "limit_activations"
                case expiresAt = "expires_at"
            }
        }

        let response = try decode(PolarLicenseKeyResponse.self, from: data)

        return License(
            key: response.key,
            isValid: true,
            status: response.status,
            expiresAt: response.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            activationLimit: response.limitActivations,
            activationUsage: response.usage,
            instanceId: nil
        )
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LicenseCheckError.invalidResponse
            }
            return (data, httpResponse)
        } catch let error as URLError {
            throw LicenseCheckError.networkError(error)
        } catch let error as LicenseCheckError {
            throw error
        } catch {
            throw LicenseCheckError.codingError(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LicenseCheckError.codingError(error)
        }
    }

    /// Same two response shapes as MacGroom's mapper — see that file's doc
    /// comment (404 = not found under this org, 422 = malformed request).
    private func mapErrorResponse(status: Int, data: Data) -> LicenseCheckError {
        let message = errorMessage(from: data)
        switch status {
        case 404:
            return .invalidLicenseKey
        case 403, 401:
            return .licenseDisabled
        default:
            if let message {
                let lower = message.lowercased()
                if lower.contains("expired") {
                    return .licenseExpired
                } else if lower.contains("disabled") || lower.contains("revoked") {
                    return .licenseDisabled
                } else if lower.contains("activation limit") || lower.contains("usage limit") {
                    return .activationLimitExceeded
                }
            }
            return .unknown(message ?? "License check failed (HTTP \(status)).")
        }
    }

    private func errorMessage(from data: Data) -> String? {
        struct FlatError: Decodable { let error: String?; let detail: String? }
        struct ValidationDetail: Decodable { let msg: String }
        struct ValidationError: Decodable { let detail: [ValidationDetail] }

        if let flat = try? JSONDecoder().decode(FlatError.self, from: data) {
            return flat.detail ?? flat.error
        }
        if let validation = try? JSONDecoder().decode(ValidationError.self, from: data) {
            return validation.detail.map(\.msg).joined(separator: "; ")
        }
        return String(data: data, encoding: .utf8)
    }

    private func getCachedLicense(_ licenseKey: String) -> (Date, License)? {
        SecureLicenseCache.readLicense(licenseKey)
    }

    private func setCachedLicense(_ licenseKey: String, _ license: License) {
        SecureLicenseCache.writeLicense(licenseKey, license)
    }
}
