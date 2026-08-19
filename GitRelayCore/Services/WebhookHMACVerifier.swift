import CryptoKit
import Foundation
import Security

/// Verifies provider webhook signatures. Secrets must come from Keychain — never log them.
nonisolated enum WebhookHMACVerifier {
    /// GitHub / Gitea style: `X-Hub-Signature-256: sha256=<hex>`.
    static func githubSignatureHeader(payload: Data, secret: String) -> String {
        "sha256=\(hexHMACSHA256(payload: payload, secret: secret))"
    }

    static func verifyGitHubSignature(payload: Data, secret: String, signatureHeader: String?) -> Bool {
        guard let signatureHeader else { return false }
        let expected = githubSignatureHeader(payload: payload, secret: secret)
        return constantTimeEqual(
            expected.lowercased(),
            signatureHeader.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    /// GitLab style: `X-Gitlab-Token` equals the shared secret (not HMAC).
    static func verifyGitLabToken(secret: String, tokenHeader: String?) -> Bool {
        guard let tokenHeader else { return false }
        return constantTimeEqual(
            secret,
            tokenHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Accept either GitHub HMAC or GitLab token header when present.
    static func verify(
        payload: Data,
        secret: String,
        githubSignatureHeader: String?,
        gitlabTokenHeader: String?
    ) -> Bool {
        if githubSignatureHeader != nil {
            return verifyGitHubSignature(
                payload: payload,
                secret: secret,
                signatureHeader: githubSignatureHeader
            )
        }
        if gitlabTokenHeader != nil {
            return verifyGitLabToken(secret: secret, tokenHeader: gitlabTokenHeader)
        }
        return false
    }

    static func generateSecret(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: max(16, byteCount))
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        // Extremely unlikely fallback — still non-empty random-looking material.
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func hexHMACSHA256(payload: Data, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Timing-safe equality for equal-length UTF-8 strings; unequal lengths always fail.
    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var diff: UInt8 = 0
        for index in left.indices {
            diff |= left[index] ^ right[index]
        }
        return diff == 0
    }
}
