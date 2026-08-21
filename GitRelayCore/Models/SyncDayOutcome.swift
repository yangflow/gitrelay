import Foundation

nonisolated struct SyncDayOutcome: Codable, Equatable, Sendable {
    var successes: Int
    var failures: Int

    init(successes: Int = 0, failures: Int = 0) {
        self.successes = max(0, successes)
        self.failures = max(0, failures)
    }

    mutating func recordSync(error: String?) {
        if error == nil {
            successes += 1
        } else {
            failures += 1
        }
    }
}
