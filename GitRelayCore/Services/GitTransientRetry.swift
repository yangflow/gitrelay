import Foundation

/// Classification of a git (or LFS-via-git) failure for in-run retry.
enum GitErrorRetryability: Equatable, Sendable {
    /// Transient network / remote blip — safe to retry within the same sync.
    case retryable(reason: String)
    /// Auth, permission, policy, corruption, or other permanent failure — do not retry.
    case nonRetryable
    /// User cancel or process interrupt — stop immediately.
    case cancelled
}

/// Pure classifier for transient git errors. Matches the small set of network patterns
/// already used by `SyncEngine.classifyError`, plus explicit cousins from issue #44
/// (connection reset, HTTP 5xx). Does not invent a large matcher.
enum GitTransientErrorClassifier {
    static func classify(_ error: Error) -> GitErrorRetryability {
        if error is CancellationError {
            return .cancelled
        }
        if let gitError = error as? GitError {
            switch gitError {
            case .cancelled:
                return .cancelled
            case .gitNotFound:
                return .nonRetryable
            case .processError(_, let message):
                return classifyMessage(message)
            }
        }
        if error is DestructivePushError {
            return .nonRetryable
        }
        if error is SyncEngineError {
            return .nonRetryable
        }
        if error is ArchiveError {
            return .nonRetryable
        }
        return classifyMessage(error.localizedDescription)
    }

    static func classifyMessage(_ raw: String) -> GitErrorRetryability {
        let message = SyncEngine.redactCredentials(raw)
        let lower = message.lowercased()

        if isCancelledMessage(lower) {
            return .cancelled
        }
        if isAuthOrPermission(lower) {
            return .nonRetryable
        }
        if isLocalCorruption(lower) {
            return .nonRetryable
        }
        if let reason = transientNetworkReason(in: lower) {
            return .retryable(reason: reason)
        }
        return .nonRetryable
    }

    // MARK: - Matchers

    private static func isCancelledMessage(_ lower: String) -> Bool {
        lower.contains("operation cancelled") || lower == "cancelled"
    }

    private static func isAuthOrPermission(_ lower: String) -> Bool {
        lower.contains("authentication failed")
            || lower.contains("permission denied")
            || lower.contains("could not read username")
            || lower.contains("invalid username or password")
            || lower.contains("access denied")
            || lower.contains("terminal prompts disabled")
            || lower.contains("publickey")
            || (lower.contains("authentication") && lower.contains("failed"))
    }

    private static func isLocalCorruption(_ lower: String) -> Bool {
        lower.contains("corrupt")
            || lower.contains("fsck")
            || lower.contains("bad object")
            || lower.contains("pack file")
            || lower.contains("packfile")
            || lower.contains("loose object")
            || lower.contains("incorrect header check")
    }

    /// Returns a short English reason for logs when the message looks like a transient network fault.
    private static func transientNetworkReason(in lower: String) -> String? {
        if lower.contains("could not resolve host") {
            return "Could not resolve host"
        }
        if lower.contains("connection timed out") || lower.contains("connection timeout") {
            return "Connection timed out"
        }
        if lower.contains("connection reset") || lower.contains("connection was reset") {
            return "Connection reset"
        }
        if lower.contains("network is unreachable") {
            return "Network is unreachable"
        }
        if lower.contains("timed out") || lower.contains("timeout") {
            return "Network timeout"
        }
        if containsHTTP5xx(lower) {
            return "HTTP 5xx"
        }
        if lower.contains("temporarily unavailable") || lower.contains("try again later") {
            return "Temporary remote failure"
        }
        return nil
    }

    private static func containsHTTP5xx(_ lower: String) -> Bool {
        // git: "The requested URL returned error: 502"
        // libcurl / git: "RPC failed; HTTP 502" / "The remote end hung up unexpectedly"
        for code in [500, 501, 502, 503, 504, 520, 521, 522, 523, 524] {
            if lower.contains("error: \(code)")
                || lower.contains("http \(code)")
                || lower.contains("status code \(code)")
                || lower.contains("returned error: \(code)") {
                return true
            }
        }
        return false
    }
}

/// Configurable in-run retry budget. Delays are 2s / 8s / 32s (then ×4), clamped so
/// total sleep never exceeds three minutes.
struct GitRetryPolicy: Equatable, Sendable {
    static let defaultMaxAttempts = 3
    static let maxTotalWaitSeconds: TimeInterval = 180
    static let baseDelaySeconds: [TimeInterval] = [2, 8, 32]

    /// Total attempts (including the first). Always ≥ 1 and limited by `maxTotalWaitSeconds`.
    let maxAttempts: Int

    static let `default` = GitRetryPolicy(maxAttempts: defaultMaxAttempts)

    init(maxAttempts: Int = defaultMaxAttempts) {
        self.maxAttempts = Self.clampedMaxAttempts(maxAttempts)
    }

    /// Delay to wait after a failed `attempt` (1-based) before starting the next attempt.
    func delayAfterAttempt(_ attempt: Int) -> TimeInterval? {
        guard attempt >= 1, attempt < maxAttempts else { return nil }
        let schedule = Self.delaySchedule(maxAttempts: maxAttempts)
        let index = attempt - 1
        guard index < schedule.count else { return nil }
        return schedule[index]
    }

    static func clampedMaxAttempts(_ requested: Int) -> Int {
        let asked = max(1, requested)
        let schedule = delaySchedule(maxAttempts: asked)
        return schedule.count + 1
    }

    /// Delays between consecutive attempts for a given attempt budget.
    static func delaySchedule(maxAttempts: Int) -> [TimeInterval] {
        let gaps = max(0, maxAttempts - 1)
        guard gaps > 0 else { return [] }

        var delays: [TimeInterval] = []
        var total: TimeInterval = 0
        for index in 0..<gaps {
            let delay: TimeInterval
            if index < baseDelaySeconds.count {
                delay = baseDelaySeconds[index]
            } else {
                delay = (delays.last ?? baseDelaySeconds.last ?? 32) * 4
            }
            if total + delay > maxTotalWaitSeconds {
                break
            }
            delays.append(delay)
            total += delay
        }
        return delays
    }
}

/// Runs a throwing async operation with exponential backoff for transient git errors.
/// Uses an injectable sleeper so tests never wait the real 2/8/32 seconds.
@MainActor
enum GitRetryExecutor {
    static func run<T>(
        policy: GitRetryPolicy = .default,
        isCancelled: @Sendable () -> Bool = { false },
        sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil,
        onRetry: ((_ nextAttempt: Int, _ maxAttempts: Int, _ reason: String) async -> Void)? = nil,
        beforeRetry: (() async throws -> Void)? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        let sleepHandler = sleep ?? { seconds in
            try await interruptibleSleep(seconds: seconds, isCancelled: isCancelled)
        }

        var attempt = 1
        while true {
            if isCancelled() {
                throw GitError.cancelled
            }

            do {
                return try await operation()
            } catch {
                if isCancelled() {
                    throw GitError.cancelled
                }

                switch GitTransientErrorClassifier.classify(error) {
                case .cancelled:
                    throw GitError.cancelled
                case .nonRetryable:
                    throw error
                case .retryable(let reason):
                    guard let delay = policy.delayAfterAttempt(attempt) else {
                        throw error
                    }
                    let nextAttempt = attempt + 1
                    // Stop before sleeping when the user already cancelled.
                    if isCancelled() {
                        throw GitError.cancelled
                    }
                    if let onRetry {
                        await onRetry(nextAttempt, policy.maxAttempts, reason)
                    }
                    if let beforeRetry {
                        try await beforeRetry()
                    }
                    if isCancelled() {
                        throw GitError.cancelled
                    }
                    try await sleepHandler(delay)
                    if isCancelled() {
                        throw GitError.cancelled
                    }
                    attempt = nextAttempt
                }
            }
        }
    }

    /// Sleep in short slices so cancel mid-backoff does not wait out the remaining delay.
    nonisolated static func interruptibleSleep(
        seconds: TimeInterval,
        isCancelled: @Sendable () -> Bool
    ) async throws {
        var remaining = max(0, seconds)
        let slice: TimeInterval = 0.25
        while remaining > 0 {
            if isCancelled() {
                throw GitError.cancelled
            }
            let step = min(slice, remaining)
            try await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            remaining -= step
        }
        if isCancelled() {
            throw GitError.cancelled
        }
    }
}

enum GitRetryLog {
    /// User-visible / sync-log line. `reason` must already be redacted if it may contain URLs.
    static func line(attempt: Int, maxAttempts: Int, reason: String) -> String {
        let safeReason = SyncEngine.redactCredentials(reason)
        return String(
            localized: "Retry \(attempt) of \(maxAttempts), reason: \(safeReason)"
        )
    }
}
