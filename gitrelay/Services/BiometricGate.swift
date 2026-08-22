import Foundation

/// Enforces biometric authorization for sensitive actions according to user preferences.
struct BiometricGate: Sendable {
    let policy: SensitiveActionPolicy
    let authenticator: BiometricAuthenticating

    func authorize(action: SensitiveAction) async -> Bool {
        guard policy.requiresAuthentication(for: action) else { return true }
        return await authenticator.authenticate(reason: localizedReason(for: action))
    }

    private func localizedReason(for action: SensitiveAction) -> String {
        switch action {
        case .revealToken:
            return String.loc("Authenticate to show the token in plaintext.")
        case .deleteRepository:
            return String.loc("Authenticate to delete this repository and its local mirror.")
        case .changeTargetHost:
            return String.loc("Authenticate to change the mirror target to a different host.")
        }
    }
}
