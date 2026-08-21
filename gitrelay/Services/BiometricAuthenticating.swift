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
    private nonisolated(unsafe) var storedLastReason: String?
    private nonisolated(unsafe) var storedResult: Bool

    var lastReason: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedLastReason
    }

    var result: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedResult
        }
        set {
            lock.lock()
            storedResult = newValue
            lock.unlock()
        }
    }

    init(result: Bool = true) {
        storedResult = result
    }

    func authenticate(reason: String) async -> Bool {
        record(reason: reason)
    }

    /// Synchronous lock use stays off the async function body (avoids priority-inversion warning).
    private nonisolated func record(reason: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storedLastReason = reason
        return storedResult
    }
}
