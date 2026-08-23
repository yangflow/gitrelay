import Foundation

enum RepoRowHealthPresentation {
    static let staleThreshold: TimeInterval = 86_400
    static let failureEscalationThreshold = 3

    enum CaptionKind: Equatable {
        case needsCredentials
        case diverged
        case neverSynced
        case lastSync(Date)
        case queued
        case syncing(String)
    }

    struct Caption: Equatable {
        let kind: CaptionKind
        let isStale: Bool
    }

    static func caption(
        for repo: MirrorSnapshot,
        status: SyncStatus,
        syncPhase: SyncPhase? = nil,
        now: Date = .now
    ) -> Caption {
        if case .queued = status {
            return Caption(kind: .queued, isStale: false)
        }
        if case .syncing = status {
            let text = syncPhase?.displayCaption ?? String(localized: "Syncing...")
            return Caption(kind: .syncing(text), isStale: false)
        }

        let kind: CaptionKind
        if repo.needsCredentials {
            kind = .needsCredentials
        } else if case .diverged = status {
            kind = .diverged
        } else if let lastSyncedAt = repo.lastSyncedAt {
            kind = .lastSync(lastSyncedAt)
        } else {
            kind = .neverSynced
        }

        return Caption(kind: kind, isStale: isStale(for: repo, now: now))
    }

    static func isStale(for repo: MirrorSnapshot, now: Date = .now) -> Bool {
        guard let lastSuccessfulSyncedAt = repo.lastSuccessfulSyncedAt else {
            return true
        }
        return now.timeIntervalSince(lastSuccessfulSyncedAt) > staleThreshold
    }

    static func showsFailureBadge(for repo: MirrorSnapshot) -> Bool {
        repo.consecutiveFailureCount >= failureEscalationThreshold
    }

    static func failureBadgeCount(for repo: MirrorSnapshot) -> Int? {
        let count = repo.consecutiveFailureCount
        guard count >= failureEscalationThreshold else { return nil }
        return count
    }
}
