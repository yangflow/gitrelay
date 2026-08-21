import Foundation

enum RepoSyncStatusKind: String, Codable, Equatable, Sendable {
    case success
    case failure
    case syncing
    case queued
    case diverged
    case unknown
}

struct RepoSyncStatusSnapshot: Equatable, Sendable {
    var repoName: String
    var status: RepoSyncStatusKind
    var lastSyncedAt: Date?
    var message: String?
}
