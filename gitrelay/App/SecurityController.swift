import Observation

@MainActor
@Observable
final class SecurityController {
    let preferences: SecurityPreferencesStore
    private let authenticator: BiometricAuthenticating

    init(
        preferences: SecurityPreferencesStore,
        authenticator: BiometricAuthenticating? = nil
    ) {
        self.preferences = preferences
        self.authenticator = authenticator ?? LocalAuthenticationClient()
    }

    func authorize(_ action: SensitiveAction) async -> Bool {
        let gate = BiometricGate(
            policy: SensitiveActionPolicy(preferences: preferences.preferences),
            authenticator: authenticator
        )
        return await gate.authorize(action: action)
    }
}
