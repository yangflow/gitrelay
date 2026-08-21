import Foundation

enum SyncStatus: Equatable {
    case unknown
    case idle
    case ahead(Int)
    case syncing
    /// Waiting for a global concurrency slot; distinct from `.syncing` (no git yet).
    case queued
    case diverged(String)
    case failed(String)
}
