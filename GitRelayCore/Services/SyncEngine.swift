import Foundation

nonisolated enum SyncEvent: Sendable {
    case started
    case phase(SyncPhase)
    case log(String)
    case statusChanged(SyncStatus)
    case completed(SyncRecord)
    case failed(String, SyncRecord)
}

@MainActor
final class SyncEngine {
    private let repo: RepoConfig
    private let runner = GitRunner()
    private let archiveService = FilesystemArchiveService()
    private let retryPolicy: GitRetryPolicy
    private let cancellation = SyncCancellationFlag()
    private var record: SyncRecord
    private var lfsReadyToPush = false

    var onEvent: ((SyncEvent) -> Void)?

    /// Called when `.strict` policy needs an explicit continue/cancel decision.
    /// Return `true` to proceed with the destructive push, `false` to block.
    var confirmDestructivePush: ((DestructivePushPlan, MirrorTarget) async -> Bool)?

    /// Called after a successful git mirror push when `repo.mirrorReleases` is enabled.
    var mirrorReleases: ((RepoConfig, MirrorTarget, @escaping @Sendable (String) -> Void) async throws -> Void)?

    init(repo: RepoConfig, retryPolicy: GitRetryPolicy = .default) {
        self.repo = repo
        self.retryPolicy = retryPolicy
        self.record = SyncRecord(repoID: repo.id)
    }

    func run() async {
        emit(.started)
        emit(.statusChanged(.syncing))

        let mirrorPath = MirrorStore.mirrorPath(for: repo.id).path
        let srcAuth = repo.srcAuth
        let rawSrcURL = repo.srcURL
        let srcURL = authenticatedURL(url: rawSrcURL, auth: srcAuth)
        let srcEnv = buildEnv(for: srcAuth)
        let enabledTargets = repo.enabledTargets
        let lfsService = LFSMirrorService(runner: runner)

        do {
            // 1. Clone or fetch from src once
            if repo.usesSelectiveRefSync {
                log(GitSyncArguments.partialSyncLogLine)
                if MirrorStore.mirrorExists(for: repo.id) {
                    let phase = SyncPhase(.fetchingSource)
                    emit(.phase(phase))
                    log("Fetching selected refs from source...")
                    try await withTransientRetry(log: { self.log($0) }) {
                        try await self.runner.fetchSource(
                            mirrorPath: mirrorPath,
                            depth: self.repo.depth,
                            refSpecs: self.repo.resolvedRefSpecs,
                            env: srcEnv,
                            onProgressLine: progressCallback(for: phase)
                        )
                    }
                    log("Fetch complete.")
                } else {
                    let phase = SyncPhase(.cloningSource)
                    emit(.phase(phase))
                    log("Initializing partial mirror (first time)...")
                    let repoID = repo.id
                    do {
                        try await withTransientRetry(
                            log: { self.log($0) },
                            beforeRetry: { try? MirrorStore.deleteMirror(for: repoID) }
                        ) {
                            try await self.runner.initBareMirror(at: mirrorPath, env: srcEnv)
                            try await self.runner.addRemote(
                                mirrorPath: mirrorPath,
                                name: "origin",
                                url: srcURL,
                                env: srcEnv
                            )
                            try await self.runner.fetchSource(
                                mirrorPath: mirrorPath,
                                depth: self.repo.depth,
                                refSpecs: self.repo.resolvedRefSpecs,
                                env: srcEnv,
                                onProgressLine: progressCallback(for: phase)
                            )
                        }
                    } catch {
                        try? MirrorStore.deleteMirror(for: repo.id)
                        throw error
                    }
                    log("Partial clone complete.")
                }
            } else if MirrorStore.mirrorExists(for: repo.id) {
                let phase = SyncPhase(.fetchingSource)
                emit(.phase(phase))
                log("Fetching from source...")
                try await withTransientRetry(log: { self.log($0) }) {
                    try await self.runner.fetchPrune(
                        mirrorPath: mirrorPath,
                        env: srcEnv,
                        onProgressLine: progressCallback(for: phase)
                    )
                }
                log("Fetch complete.")
            } else {
                let phase = SyncPhase(.cloningSource)
                emit(.phase(phase))
                log("Cloning source (first time)...")
                let repoID = repo.id
                do {
                    try await withTransientRetry(
                        log: { self.log($0) },
                        beforeRetry: { try? MirrorStore.deleteMirror(for: repoID) }
                    ) {
                        try await self.runner.cloneMirror(
                            srcURL: srcURL,
                            mirrorPath: mirrorPath,
                            env: srcEnv,
                            onProgressLine: progressCallback(for: phase)
                        )
                    }
                } catch {
                    try? MirrorStore.deleteMirror(for: repo.id)
                    throw error
                }
                log("Clone complete.")
            }

            // 1b. Optional Git LFS fetch into the local bare mirror (src → local only).
            // LFS goes through GitRunner; transient failures use the same retry classifier.
            let lfsPhase = SyncPhase(.fetchingLFS)
            let lfsPrepare = try await withTransientRetry(log: { self.log($0) }) {
                try await lfsService.prepareAfterSourceFetch(
                    mode: self.repo.lfsMirrorMode,
                    mirrorPath: mirrorPath,
                    env: srcEnv,
                    log: { [weak self] line in
                        // Emit LFS phase when the service starts fetching.
                        if line == LFSMirrorMessages.fetching {
                            self?.emit(.phase(lfsPhase))
                        }
                        self?.log(SyncEngine.redactCredentials(line))
                    },
                    onProgressLine: progressCallback(for: lfsPhase)
                )
            }
            lfsReadyToPush = (lfsPrepare == .readyToPush)

            guard !enabledTargets.isEmpty else {
                throw SyncEngineError.noEnabledTargets
            }

            // 2. Sync each enabled target independently
            var targetResults: [TargetSyncResult] = []
            for target in enabledTargets {
                let result = await syncToTarget(target, mirrorPath: mirrorPath, lfsService: lfsService)
                targetResults.append(result)
            }
            record.targetResults = targetResults

            let allSucceeded = SyncRecord.aggregateSucceeded(from: targetResults)
            record.succeeded = allSucceeded
            record.finishedAt = Date()
            record.commitsBefore = targetResults.compactMap(\.commitsBefore).max()
            record.commitsAfter = allSucceeded ? 0 : nil

            if allSucceeded {
                log("All targets synced successfully. ✓")
                emit(.statusChanged(.idle))
                emit(.completed(record))
            } else if let message = SyncRecord.aggregateErrorMessage(from: targetResults) {
                log(String(localized: "Error: \(message)"))
                emit(.failed(message, record))
                emit(.statusChanged(.failed(message)))
            } else {
                let message = "Sync failed"
                emit(.failed(message, record))
                emit(.statusChanged(.failed(message)))
            }

        } catch GitError.cancelled {
            log("Sync cancelled.")
            record.finishedAt = Date()
            emit(.failed("Cancelled", record))
            emit(.statusChanged(.unknown))

        } catch {
            let message = classifyError(error)
            log(String(localized: "Error: \(message)"))
            record.finishedAt = Date()
            emit(.failed(message, record))
            emit(.statusChanged(.failed(message)))
        }
    }

    func cancel() {
        cancellation.cancel()
        Task {
            await runner.cancel()
            await archiveService.cancel()
        }
    }

    // MARK: - Private

    private func syncToTarget(
        _ target: MirrorTarget,
        mirrorPath: String,
        lfsService: LFSMirrorService
    ) async -> TargetSyncResult {
        switch target.kind {
        case .gitRemote:
            return await pushToTarget(target, mirrorPath: mirrorPath, lfsService: lfsService)
        case .filesystem:
            return await archiveToTarget(target, mirrorPath: mirrorPath)
        }
    }

    private func archiveToTarget(_ target: MirrorTarget, mirrorPath: String) async -> TargetSyncResult {
        let label = target.displayLabel
        var result = TargetSyncResult(targetID: target.id, targetURL: label)

        func targetLog(_ line: String) {
            result.logLines.append(line)
            emit(.log("[\(label)] \(line)"))
        }

        emit(.phase(SyncPhase(.archivingTarget(label))))
        targetLog("Target: \(label) (filesystem archive)")

        do {
            _ = try await archiveService.archiveMirror(
                repo: repo,
                target: target,
                mirrorPath: mirrorPath,
                log: sendableTargetLog(targetLog)
            )
            result.succeeded = true
        } catch {
            let message = classifyError(error)
            targetLog(String(localized: "Error: \(message)"))
            result.error = message
            result.succeeded = false
        }

        return result
    }

    private func pushToTarget(
        _ target: MirrorTarget,
        mirrorPath: String,
        lfsService: LFSMirrorService
    ) async -> TargetSyncResult {
        var result = TargetSyncResult(targetID: target.id, targetURL: target.displayLabel)
        let rawDstURL = target.url
        let dstURL = authenticatedURL(url: rawDstURL, auth: target.auth)
        let dstEnv = buildEnv(for: target.auth)

        func targetLog(_ line: String) {
            let safe = SyncEngine.redactCredentials(line)
            result.logLines.append(safe)
            emit(.log("[\(rawDstURL)] \(safe)"))
        }

        let pushPhase = SyncPhase(.pushingTarget(rawDstURL))
        emit(.phase(pushPhase))
        targetLog("Target: \(rawDstURL)")

        do {
            targetLog("Checking destination...")
            var commitsBefore = 0
            do {
                try await withTransientRetry(log: targetLog) {
                    try await self.runner.fetchDstRefs(
                        mirrorPath: mirrorPath,
                        dstURL: dstURL,
                        env: dstEnv
                    )
                }
                commitsBefore = (try? await runner.countCommitsAhead(mirrorPath: mirrorPath)) ?? 0
                targetLog("Source is \(commitsBefore) commit(s) ahead of destination.")
            } catch {
                targetLog("Note: Could not read destination refs — first push? (\(error.localizedDescription))")
            }
            result.commitsBefore = commitsBefore

            targetLog("Checking mirror push impact...")
            let pushRefSpecs = GitSyncArguments.pushRefSpecs(from: repo.resolvedRefSpecs)
            let plan: DestructivePushPlan
            if repo.usesSelectiveRefSync {
                targetLog("Using selective ref push (not a complete mirror backup).")
                plan = try await withTransientRetry(log: targetLog) {
                    try await self.runner.pushSelectiveRefsDryRun(
                        mirrorPath: mirrorPath,
                        dstURL: dstURL,
                        refSpecs: pushRefSpecs,
                        env: dstEnv
                    )
                }
            } else {
                plan = try await withTransientRetry(log: targetLog) {
                    try await self.runner.pushMirrorDryRun(
                        mirrorPath: mirrorPath,
                        dstURL: dstURL,
                        env: dstEnv
                    )
                }
            }
            if plan.isDestructive {
                targetLog("Dry-run detected destructive changes: \(plan.summary).")
                plan.deletedRefs.forEach { targetLog("  delete: \($0)") }
                plan.forcedUpdateRefs.forEach { targetLog("  force-update: \($0)") }

                if repo.destructivePushPolicy.requiresConfirmation(for: plan) {
                    targetLog("Waiting for confirmation of destructive push...")
                    let confirmed = await confirmDestructivePush?(plan, target) ?? false
                    guard confirmed else {
                        throw DestructivePushError.blocked(plan)
                    }
                    targetLog("User confirmed destructive push; continuing.")
                } else {
                    targetLog("Destructive push policy is automatic; continuing.")
                }
            } else {
                targetLog("Dry-run found no destructive ref changes.")
            }

            targetLog("Pushing to destination...")
            emit(.phase(pushPhase))
            if repo.usesSelectiveRefSync {
                try await withTransientRetry(log: targetLog) {
                    try await self.runner.pushSelectiveRefs(
                        mirrorPath: mirrorPath,
                        dstURL: dstURL,
                        refSpecs: pushRefSpecs,
                        env: dstEnv,
                        onProgressLine: progressCallback(for: pushPhase)
                    )
                }
            } else {
                try await withTransientRetry(log: targetLog) {
                    try await self.runner.pushMirror(
                        mirrorPath: mirrorPath,
                        dstURL: dstURL,
                        env: dstEnv,
                        onProgressLine: progressCallback(for: pushPhase)
                    )
                }
            }
            targetLog("Push complete. ✓")

            if lfsReadyToPush {
                let lfsPushPhase = SyncPhase(.pushingLFS(rawDstURL))
                emit(.phase(lfsPushPhase))
                do {
                    try await withTransientRetry(log: targetLog) {
                        try await lfsService.pushToDestination(
                            mirrorPath: mirrorPath,
                            remoteURL: dstURL,
                            env: dstEnv,
                            log: targetLog,
                            onProgressLine: progressCallback(for: lfsPushPhase)
                        )
                    }
                } catch {
                    let message = classifyError(error)
                    targetLog(String(localized: "LFS push error: \(message)"))
                    result.error = message
                    result.succeeded = false
                    return result
                }
            }

            if repo.mirrorReleases, let mirrorReleases {
                targetLog("Mirroring releases...")
                do {
                    try await mirrorReleases(repo, target, sendableTargetLog(targetLog))
                    targetLog("Release mirror complete. ✓")
                } catch {
                    let message = classifyError(error)
                    targetLog("Release mirror error: \(message)")
                    result.error = message
                    result.succeeded = false
                    return result
                }
            }

            result.succeeded = true
        } catch {
            let message = classifyError(error)
            targetLog(String(localized: "Error: \(message)"))
            result.error = message
            result.succeeded = false
        }

        return result
    }

    private func log(_ line: String) {
        record.logLines.append(line)
        emit(.log(line))
    }

    private func emit(_ event: SyncEvent) {
        onEvent?(event)
    }

    /// Builds a thread-safe progress callback that never surfaces raw git stderr to the UI.
    private func progressCallback(for phase: SyncPhase) -> @Sendable (String) -> Void {
        let bridge = SyncPhaseProgressBridge(engine: self, phase: phase)
        return { line in
            bridge.handleLine(line)
        }
    }

    /// Wraps a MainActor log sink as `@Sendable` without stripping isolation at the call site.
    private func sendableTargetLog(
        _ onLine: @escaping @MainActor (String) -> Void
    ) -> @Sendable (String) -> Void {
        let bridge = SyncTargetLogBridge(onLine: onLine)
        return { line in
            bridge.handleLine(line)
        }
    }

    fileprivate func applyParsedProgress(_ phase: SyncPhase) {
        emit(.phase(phase))
    }

    /// Retries transient network git failures within this sync run. Cancel stops before the next sleep.
    private func withTransientRetry<T>(
        log logLine: @escaping (String) -> Void,
        beforeRetry: (() async throws -> Void)? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        let flag = cancellation
        return try await GitRetryExecutor.run(
            policy: retryPolicy,
            isCancelled: { flag.isCancelled },
            onRetry: { nextAttempt, maxAttempts, reason in
                let line = GitRetryLog.line(
                    attempt: nextAttempt,
                    maxAttempts: maxAttempts,
                    reason: reason
                )
                logLine(SyncEngine.redactCredentials(line))
            },
            beforeRetry: beforeRetry,
            operation: operation
        )
    }

    private func authenticatedURL(url: String, auth: AuthConfig) -> String {
        guard case .httpsToken(let tag) = auth,
              let token = try? KeychainService.loadToken(tag: tag) else { return url }
        guard var components = URLComponents(string: url) else { return url }
        components.user = token
        return components.string ?? url
    }

    private func classifyError(_ error: Error) -> String {
        SyncFailureClassifier.classifyError(error)
    }

    nonisolated static func redactCredentials(_ message: String) -> String {
        var result = message
        if let regex = try? NSRegularExpression(pattern: "https://[^@]+@") {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "https://****@"
            )
        }
        return result
    }

    private func buildEnv(for auth: AuthConfig) -> [String: String] {
        switch auth {
        case .sshAgent:
            return [:]
        case .sshKey(let path):
            return ["GIT_SSH_COMMAND": "ssh -i \(path) -o StrictHostKeyChecking=accept-new -o BatchMode=yes"]
        case .httpsToken:
            return ["GIT_TERMINAL_PROMPT": "0"]
        }
    }
}

/// Forwards parsed git progress onto the main-actor SyncEngine without capturing it in a Sendable closure.
private nonisolated final class SyncPhaseProgressBridge: @unchecked Sendable {
    private nonisolated(unsafe) weak var engine: SyncEngine?
    private let phase: SyncPhase

    init(engine: SyncEngine, phase: SyncPhase) {
        self.engine = engine
        self.phase = phase
    }

    func handleLine(_ line: String) {
        let safe = SyncEngine.redactCredentials(line)
        guard let detail = GitProgressParser.detail(from: safe) else { return }
        let updated = phase.withProgress(detail)
        Task { @MainActor [weak engine] in
            engine?.applyParsedProgress(updated)
        }
    }
}

/// Forwards target log lines onto a MainActor sink without converting a MainActor function to `@Sendable`.
private nonisolated final class SyncTargetLogBridge: @unchecked Sendable {
    private let onLine: @MainActor (String) -> Void

    init(onLine: @escaping @MainActor (String) -> Void) {
        self.onLine = onLine
    }

    func handleLine(_ line: String) {
        Task { @MainActor in
            onLine(line)
        }
    }
}

nonisolated enum SyncEngineError: LocalizedError {
    case noEnabledTargets

    var errorDescription: String? {
        switch self {
        case .noEnabledTargets:
            return "No enabled mirror targets"
        }
    }
}

/// Thread-safe cancel flag shared with the retry executor (which is not MainActor-isolated).
nonisolated final class SyncCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
