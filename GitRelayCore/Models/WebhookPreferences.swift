import Foundation

/// App-level webhook listener preferences (no secrets — HMAC stays in Keychain).
nonisolated struct WebhookPreferences: Equatable, Sendable {
    /// When false (default), the embedded HTTP listener is not started.
    var listenerEnabled: Bool

    /// Optional public exposure mode; default `.off`.
    var exposureMode: WebhookExposureMode

    /// Optional public base URL such as `https://abc.trycloudflare.com` (no trailing path).
    var publicBaseURL: String

    static let `default` = WebhookPreferences(
        listenerEnabled: false,
        exposureMode: .off,
        publicBaseURL: ""
    )

    var normalizedPublicBaseURL: String {
        var value = publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
