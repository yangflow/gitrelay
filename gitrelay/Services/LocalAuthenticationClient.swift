import Foundation
import LocalAuthentication

/// Production LocalAuthentication wrapper.
struct LocalAuthenticationClient: BiometricAuthenticating {
    func authenticate(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            var error: NSError?
            let policy: LAPolicy = .deviceOwnerAuthentication
            guard context.canEvaluatePolicy(policy, error: &error) else {
                continuation.resume(returning: false)
                return
            }
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
