import Foundation

enum RepoIntentSupport {
    static func repo(matchingName name: String, in repos: [RepoConfig]) -> RepoConfig? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return repos.first {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
    }

    static func makeSnapshot(
        repo: RepoConfig,
        runtimeStatus: SyncStatus?,
        isSyncInProgress: Bool
    ) -> RepoSyncStatusSnapshot {
        if isSyncInProgress {
            return RepoSyncStatusSnapshot(
                repoName: repo.name,
                status: .syncing,
                lastSyncedAt: repo.lastSyncedAt,
                message: nil
            )
        }

        if let runtimeStatus {
            switch runtimeStatus {
            case .syncing:
                return RepoSyncStatusSnapshot(
                    repoName: repo.name,
                    status: .syncing,
                    lastSyncedAt: repo.lastSyncedAt,
                    message: nil
                )
            case .queued:
                return RepoSyncStatusSnapshot(
                    repoName: repo.name,
                    status: .queued,
                    lastSyncedAt: repo.lastSyncedAt,
                    message: nil
                )
            case .failed(let message):
                return RepoSyncStatusSnapshot(
                    repoName: repo.name,
                    status: .failure,
                    lastSyncedAt: repo.lastSyncedAt,
                    message: message
                )
            case .diverged(let message):
                return RepoSyncStatusSnapshot(
                    repoName: repo.name,
                    status: .diverged,
                    lastSyncedAt: repo.lastSyncedAt ?? repo.lastVerifiedAt,
                    message: message
                )
            case .idle, .ahead:
                return persistedSnapshot(for: repo)
            case .unknown:
                break
            }
        }

        return persistedSnapshot(for: repo)
    }

    private static func persistedSnapshot(for repo: RepoConfig) -> RepoSyncStatusSnapshot {
        if let error = repo.lastSyncError {
            return RepoSyncStatusSnapshot(
                repoName: repo.name,
                status: .failure,
                lastSyncedAt: repo.lastSyncedAt,
                message: error
            )
        }

        if let detail = repo.divergedDetail {
            return RepoSyncStatusSnapshot(
                repoName: repo.name,
                status: .diverged,
                lastSyncedAt: repo.lastSyncedAt ?? repo.lastVerifiedAt,
                message: detail
            )
        }

        if repo.lastSuccessfulSyncedAt != nil {
            return RepoSyncStatusSnapshot(
                repoName: repo.name,
                status: .success,
                lastSyncedAt: repo.lastSuccessfulSyncedAt ?? repo.lastSyncedAt,
                message: nil
            )
        }

        return RepoSyncStatusSnapshot(
            repoName: repo.name,
            status: .unknown,
            lastSyncedAt: repo.lastSyncedAt,
            message: nil
        )
    }
}
