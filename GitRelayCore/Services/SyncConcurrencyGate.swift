import Foundation

/// Global sync admission control: caps concurrent clone/fetch/push and FIFO-queues the rest.
/// MainActor-only — owned by the app scheduler / view model. Process quit drops the queue.
@MainActor
final class SyncConcurrencyGate {
    static let allowedRange = 1...4
    static let defaultMaxConcurrent = 2

    private(set) var maxConcurrent: Int
    private var activeIDs: Set<UUID> = []
    private var queuedIDs: [UUID] = []

    var activeCount: Int { activeIDs.count }
    var queuedCount: Int { queuedIDs.count }
    var queuedRepoIDs: [UUID] { queuedIDs }

    init(maxConcurrent: Int = SyncConcurrencyGate.defaultMaxConcurrent) {
        self.maxConcurrent = Self.clamped(maxConcurrent)
    }

    static func clamped(_ value: Int) -> Int {
        min(max(value, allowedRange.lowerBound), allowedRange.upperBound)
    }

    enum Decision: Equatable, Sendable {
        case beginImmediately
        case enqueued
        case alreadyTracked
    }

    func isQueued(_ id: UUID) -> Bool {
        queuedIDs.contains(id)
    }

    func isActive(_ id: UUID) -> Bool {
        activeIDs.contains(id)
    }

    func request(_ id: UUID) -> Decision {
        if activeIDs.contains(id) || queuedIDs.contains(id) {
            return .alreadyTracked
        }
        if activeIDs.count < maxConcurrent {
            activeIDs.insert(id)
            return .beginImmediately
        }
        queuedIDs.append(id)
        return .enqueued
    }

    /// Removes a waiting repo from the queue. Does not affect an already-running sync.
    @discardableResult
    func cancelQueued(_ id: UUID) -> Bool {
        guard let index = queuedIDs.firstIndex(of: id) else { return false }
        queuedIDs.remove(at: index)
        return true
    }

    /// Marks an active sync finished and admits the next queued repo, if capacity allows.
    func finishActive(_ id: UUID) -> UUID? {
        activeIDs.remove(id)
        return dequeueNextIfCapacity()
    }

    /// Updates the cap and returns newly admitted repo IDs (FIFO) that should start now.
    func updateMaxConcurrent(_ value: Int) -> [UUID] {
        maxConcurrent = Self.clamped(value)
        var admitted: [UUID] = []
        while let next = dequeueNextIfCapacity() {
            admitted.append(next)
        }
        return admitted
    }

    /// Drops active and queued entries without starting anything (import replace / teardown).
    func reset() {
        activeIDs.removeAll()
        queuedIDs.removeAll()
    }

    private func dequeueNextIfCapacity() -> UUID? {
        guard activeIDs.count < maxConcurrent, !queuedIDs.isEmpty else { return nil }
        let next = queuedIDs.removeFirst()
        activeIDs.insert(next)
        return next
    }
}
