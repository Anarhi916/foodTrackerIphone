import Foundation
import DeviceCheck
import CryptoKit

// Apple App Attest (iOS). Two phases, mirroring backend/src/services/appAttest.js:
//
//   1) Enrollment (once per install): fetch a one-time challenge, generateKey() to get a
//      hardware-backed keyId, attestKey() over SHA256(challenge), then POST the attestation
//      to /v1/attest/apple/register. The keyId is cached in the Keychain on success.
//   2) Per request: build clientData = "<random>:<epochMillis>", generateAssertion() over
//      SHA256(clientData), and send X-Attest-KeyId / X-Attest-Assertion / X-Attest-Nonce.
//
// Best-effort: on the Simulator (isSupported == false) or any failure this returns nil and the
// caller falls back to X-Dev-Auth (which only a dev-mode backend accepts). A prod backend
// requires the attestation headers.
actor AppAttestService {
    static let shared = AppAttestService()

    private let service = DCAppAttestService.shared
    private let keyIdKeychainKey = "appAttestKeyId"
    private var enrollTask: Task<String?, Never>?

    private init() {}

    var isSupported: Bool { service.isSupported }

    /// Attestation headers for a protected request, or nil if unavailable
    /// (Simulator / unsupported / enrollment or assertion failed → fall back to X-Dev-Auth).
    func attestationHeaders() async -> [String: String]? {
        guard service.isSupported else { return nil }
        guard let keyId = await ensureEnrolledKeyId() else { return nil }

        // clientData = "<random>:<epochMillis>": random keeps every assertion unique,
        // the timestamp lets the backend enforce freshness. The hardware signCount
        // (embedded in the assertion's authData) is what actually blocks replays.
        let clientData = "\(UUID().uuidString):\(Int(Date().timeIntervalSince1970 * 1000))"
        let clientDataHash = Data(SHA256.hash(data: Data(clientData.utf8)))
        do {
            let assertion = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
            return [
                "X-Attest-KeyId": keyId,
                "X-Attest-Assertion": assertion.base64EncodedString(),
                "X-Attest-Nonce": clientData,
            ]
        } catch {
            // A stored key can become invalid (e.g. restored device). Drop it so the next
            // call re-enrolls, and fall back to dev auth for this request.
            KeychainService.delete(keyIdKeychainKey)
            return nil
        }
    }

    // Return a registered keyId, enrolling once if needed. Concurrent callers share one enroll.
    private func ensureEnrolledKeyId() async -> String? {
        if let keyId = KeychainService.get(keyIdKeychainKey) { return keyId }
        if let task = enrollTask { return await task.value }
        let task = Task { await self.enroll() }
        enrollTask = task
        let result = await task.value
        enrollTask = nil
        return result
    }

    private func enroll() async -> String? {
        do {
            // 1) One-time challenge from the backend.
            let challenge = try await NetworkService.shared.attestChallenge()
            // 2) Fresh hardware key.
            let keyId = try await service.generateKey()
            // 3) Attest it. clientDataHash = SHA256(challenge string) — matches the backend,
            //    which computes the expected nonce as SHA256(authData || SHA256(challenge)).
            let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
            let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
            // 4) Register the attestation; on success cache the keyId.
            try await NetworkService.shared.attestRegister(
                keyId: keyId,
                attestation: attestation.base64EncodedString(),
                challenge: challenge
            )
            KeychainService.set(keyId, for: keyIdKeychainKey)
            return keyId
        } catch {
            return nil
        }
    }
}
