import Foundation

/// Abstraction over LocalAuthentication for testability.
protocol BiometricAuthenticating: Sendable {
    func authenticate(reason: String) async -> Bool
}

/// Always succeeds; used when biometric gating is disabled.
struct PermissiveBiometricAuthenticator: BiometricAuthenticating {
    func authenticate(reason: String) async -> Bool { true }
}

/// Records the last reason and returns a fixed result; for unit tests.
final class StubBiometricAuthenticator: BiometricAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var lastReason: String?
    var result: Bool

    init(result: Bool = true) {
        self.result = result
    }

    func authenticate(reason: String) async -> Bool {
        lock.lock()
        lastReason = reason
        lock.unlock()
        return result
    }
}
