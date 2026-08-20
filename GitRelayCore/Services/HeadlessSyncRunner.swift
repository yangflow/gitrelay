import Foundation

enum HeadlessSyncError: LocalizedError, Equatable {
    case repoNotFound(String)
    case loadFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .repoNotFound(let name):
            return "No repository named \"\(name)\" was found."
        case .loadFailed(let message):
            return "Failed to load repositories: \(message)"
        case .saveFailed(let message):
            return "Failed to save repositories: \(message)"
        }
    }
}

enum HeadlessSyncRunner {
    @MainActor
    static func sync(repoName: String) async throws -> Bool {
        var repos = try loadRepos()
        guard let index = repos.firstIndex(where: {
            RepoIntentSupport.repo(matchingName: repoName, in: [$0]) != nil
        }) else {
            throw HeadlessSyncError.repoNotFound(repoName)
        }

        let repoID = repos[index].id
        let engine = SyncEngine(
            repo: repos[index],
            retryPolicy: NotificationPreferences.gitRetryPolicy()
        )
        engine.confirmDestructivePush = { plan, _ in
            !repos[index].destructivePushPolicy.requiresConfirmation(for: plan)
        }

        var latestRecord: SyncRecord?
        var failureMessage: String?

        engine.onEvent = { event in
            switch event {
            case .completed(let record):
                latestRecord = record
            case .failed(let message, let record):
                latestRecord = record
                failureMessage = message
            case .started, .log, .statusChanged, .phase:
                break
            }
        }

        await engine.run()

        guard let record = latestRecord else {
            return false
        }

        try? SyncLogStore.append(record, for: repoID)

        repos[index].recordSyncResult(at: record.finishedAt ?? .now, error: record.succeeded ? nil : failureMessage)
        do {
            try RepoStore.save(repos)
        } catch {
            throw HeadlessSyncError.saveFailed(error.localizedDescription)
        }

        if record.succeeded {
            let quota = CachePreferences.load().cacheQuotaGB
            _ = await MirrorCacheService.performCleanup(
                repos: repos,
                quotaGB: quota,
                excluding: [repoID]
            )
        }

        return record.succeeded
    }

    static func loadRepos() throws -> [RepoConfig] {
        do {
            return try RepoStore.load()
        } catch {
            throw HeadlessSyncError.loadFailed(error.localizedDescription)
        }
    }
}
