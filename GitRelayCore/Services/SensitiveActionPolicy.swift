import Foundation

/// Decides whether a sensitive action requires biometric authentication.
struct SensitiveActionPolicy: Equatable, Sendable {
    var requireBiometricForSensitive: Bool

    init(preferences: SecurityPreferences) {
        requireBiometricForSensitive = preferences.requireBiometricForSensitive
    }

    init(requireBiometricForSensitive: Bool) {
        self.requireBiometricForSensitive = requireBiometricForSensitive
    }

    func requiresAuthentication(for action: SensitiveAction) -> Bool {
        guard requireBiometricForSensitive else { return false }
        switch action {
        case .revealToken, .deleteRepository:
            return true
        case .changeTargetHost(let originalURL, let newURL):
            guard let oldHost = GitRemoteHost.host(from: originalURL),
                  let newHost = GitRemoteHost.host(from: newURL) else {
                return false
            }
            return oldHost != newHost
        }
    }
}
