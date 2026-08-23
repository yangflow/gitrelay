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
    private let plan: MirrorPlan
    private let runner: GitRunner
    private let archiveService: FilesystemArchiveService
    private let lfsCommandRunner: any LFSCommandRunning
    private let retryPolicy: GitRetryPolicy
    private let mirrorRootDirectory: URL
    private let cancellation = SyncCancellationFlag()
    private var record: SyncRecord
    private var lfsReadyToPush = false

    var onEvent: ((SyncEvent) -> Void)?

    /// Called when `.strict` policy needs the user to choose between overwriting
    /// the destination, pushing to check branches instead, or stopping the sync.
    var confirmDestructivePush: ((DestructivePushPlan, MirrorDestination) async -> DestructivePushDecision)?

    /// Called after a successful Git push when release mirroring is enabled.
    var mirrorReleases: (
        (MirrorPlan, MirrorDestination, @escaping @Sendable (String) -> Void) async throws -> Void
    )?

    init(
        plan: MirrorPlan,
        retryPolicy: GitRetryPolicy = .default,
        mirrorRootDirectory: URL = Constants.mirrorCacheDirectory,
        runner: GitRunner = GitRunner(),
        archiveService: FilesystemArchiveService? = nil,
        lfsCommandRunner: (any LFSCommandRunning)? = nil
    ) {
        self.plan = plan
        self.retryPolicy = retryPolicy
        self.mirrorRootDirectory = mirrorRootDirectory
        self.runner = runner
        self.archiveService = archiveService ?? FilesystemArchiveService()
        self.lfsCommandRunner = lfsCommandRunner ?? runner
        self.record = SyncRecord(repoID: plan.id)
    }

    func run() async {
        emit(.started)
        emit(.statusChanged(.syncing))

        let mirrorPath = MirrorStore.mirrorPath(
            for: plan.id,
            rootDirectory: mirrorRootDirectory
        ).path
        let srcAuth = plan.source.auth
        let rawSrcURL = plan.source.url
        let srcURL = authenticatedURL(url: rawSrcURL, auth: srcAuth)
        let srcEnv = buildEnv(for: srcAuth)
        let enabledTargets = plan.enabledDestinations
        let lfsService = LFSMirrorService(runner: lfsCommandRunner)

        do {
            // 1. Clone or fetch from src once
            if usesSelectiveRefSync {
                log(GitSyncArguments.partialSyncLogLine)
                if MirrorStore.mirrorExists(for: plan.id, rootDirectory: mirrorRootDirectory) {
                    let phase = SyncPhase(.fetchingSource)
                    emit(.phase(phase))
                    log("Fetching selected refs from source...")
                    try await withTransientRetry(log: { self.log($0) }) {
                        try await self.runner.fetchSource(
                            mirrorPath: mirrorPath,
                            depth: self.plan.policy.content.depth,
                            refSpecs: self.plan.policy.content.refSpecs,
                            env: srcEnv,
                            onProgressLine: progressCallback(for: phase)
                        )
                    }
                    log("Fetch complete.")
                } else {
                    let phase = SyncPhase(.cloningSource)
                    emit(.phase(phase))
                    log("Initializing partial mirror (first time)...")
                    let repoID = plan.id
                    do {
                        try await withTransientRetry(
                            log: { self.log($0) },
                            beforeRetry: {
                                try? MirrorStore.deleteMirror(
                                    for: repoID,
                                    rootDirectory: self.mirrorRootDirectory
                                )
                            }
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
                                depth: self.plan.policy.content.depth,
                                refSpecs: self.plan.policy.content.refSpecs,
                                env: srcEnv,
                                onProgressLine: progressCallback(for: phase)
                            )
                        }
                    } catch {
                        try? MirrorStore.deleteMirror(
                            for: plan.id,
                            rootDirectory: mirrorRootDirectory
                        )
                        throw error
                    }
                    log("Partial clone complete.")
                }
            } else if MirrorStore.mirrorExists(
                for: plan.id,
                rootDirectory: mirrorRootDirectory
            ) {
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
                let repoID = plan.id
                do {
                    try await withTransientRetry(
                        log: { self.log($0) },
                        beforeRetry: {
                            try? MirrorStore.deleteMirror(
                                for: repoID,
                                rootDirectory: self.mirrorRootDirectory
                            )
                        }
                    ) {
                        try await self.runner.cloneMirror(
                            srcURL: srcURL,
                            mirrorPath: mirrorPath,
                            env: srcEnv,
                            onProgressLine: progressCallback(for: phase)
                        )
                    }
                } catch {
                    try? MirrorStore.deleteMirror(
                            for: plan.id,
                        rootDirectory: mirrorRootDirectory
                    )
                    throw error
                }
                log("Clone complete.")
            }

            // 1b. Optional Git LFS fetch into the local bare mirror (src → local only).
            // LFS goes through GitRunner; transient failures use the same retry classifier.
            let lfsPhase = SyncPhase(.fetchingLFS)
            let lfsPrepare = try await withTransientRetry(log: { self.log($0) }) {
                try await lfsService.prepareAfterSourceFetch(
                    mode: self.plan.policy.content.lfsMode,
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

    private var usesSelectiveRefSync: Bool {
        !plan.policy.content.isCompleteMirror
    }

    private func syncToTarget(
        _ target: MirrorDestination,
        mirrorPath: String,
        lfsService: LFSMirrorService
    ) async -> TargetSyncResult {
        switch target.location {
        case .git:
            return await pushToTarget(target, mirrorPath: mirrorPath, lfsService: lfsService)
        case .archive(let archive):
            return await archiveToTarget(target, archive: archive, mirrorPath: mirrorPath)
        }
    }

    private func archiveToTarget(
        _ target: MirrorDestination,
        archive: ArchiveDestination,
        mirrorPath: String
    ) async -> TargetSyncResult {
        let label = target.location.displayLocation
        var result = TargetSyncResult(targetID: target.id, targetURL: label)

        func targetLog(_ line: String) {
            result.logLines.append(line)
            emit(.log("[\(label)] \(line)"))
        }

        emit(.phase(SyncPhase(.archivingTarget(label))))
        targetLog("Target: \(label) (filesystem archive)")

        do {
            _ = try await archiveService.archiveMirror(
                mirrorName: plan.name,
                destination: archive,
                mirrorPath: mirrorPath,
                log: sendableTargetLog(targetLog)
            )
            result.succeeded = true
        } catch {
            let message = classifyError(error)
            targetLog(String(localized: "Error: \(message)"))
            result.error = message
            result.failureKind = failureKind(for: error, destinationID: target.id)
            result.succeeded = false
        }

        return result
    }

    private func pushToTarget(
        _ target: MirrorDestination,
        mirrorPath: String,
        lfsService: LFSMirrorService
    ) async -> TargetSyncResult {
        guard case .git(let endpoint) = target.location else {
            return TargetSyncResult(
                targetID: target.id,
                targetURL: target.location.displayLocation,
                succeeded: false,
                error: "Expected a Git destination"
            )
        }
        var result = TargetSyncResult(targetID: target.id, targetURL: endpoint.url)
        let rawDstURL = endpoint.url
        let dstURL = authenticatedURL(url: rawDstURL, auth: endpoint.auth)
        let dstEnv = buildEnv(for: endpoint.auth)

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
            let pushRefSpecs = GitSyncArguments.pushRefSpecs(from: plan.policy.content.refSpecs)
            let impactPlan: DestructivePushPlan
            if usesSelectiveRefSync {
                targetLog("Using selective ref push (not a complete mirror backup).")
                impactPlan = try await withTransientRetry(log: targetLog) {
                    try await self.runner.pushSelectiveRefsDryRun(
                        mirrorPath: mirrorPath,
                        dstURL: dstURL,
                        refSpecs: pushRefSpecs,
                        env: dstEnv
                    )
                }
            } else {
                impactPlan = try await withTransientRetry(log: targetLog) {
                    try await self.runner.pushMirrorDryRun(
                        mirrorPath: mirrorPath,
                        dstURL: dstURL,
                        env: dstEnv
                    )
                }
            }
            var pushesToCheckBranches = false
            if impactPlan.isDestructive {
                targetLog("Dry-run detected destructive changes: \(impactPlan.summary).")
                impactPlan.deletedRefs.forEach { targetLog("  delete: \($0)") }
                impactPlan.forcedUpdateRefs.forEach { targetLog("  force-update: \($0)") }

                if plan.policy.destructivePush.requiresConfirmation(for: impactPlan) {
                    targetLog("Waiting for confirmation of destructive push...")
                    let divergence = try? await runner.countDestinationOnlyCommits(mirrorPath: mirrorPath)
                    let decision = await confirmDestructivePush?(
                        impactPlan.withDestinationOnlyCommits(divergence),
                        target
                    ) ?? .cancel

                    switch decision {
                    case .cancel:
                        throw DestructivePushError.blocked(impactPlan)
                    case .overwrite:
                        targetLog("User chose to overwrite the destination; continuing.")
                    case .checkBranch:
                        pushesToCheckBranches = true
                        targetLog("User chose check branches; the destination's own branches stay put.")
                    }
                } else {
                    targetLog("Destructive push policy is automatic; continuing.")
                }
            } else {
                targetLog("Dry-run found no destructive ref changes.")
            }

            targetLog("Pushing to destination...")
            emit(.phase(pushPhase))
            if pushesToCheckBranches {
                let checkRefSpecs = CheckBranchRefMapping.refSpecs(from: pushRefSpecs)
                targetLog("Pushing source refs under \(CheckBranchRefMapping.displayPrefix) instead.")
                checkRefSpecs.forEach { targetLog("  check branch: \($0)") }
                try await withTransientRetry(log: targetLog) {
                    try await self.runner.pushSelectiveRefs(
                        mirrorPath: mirrorPath,
                        dstURL: dstURL,
                        refSpecs: checkRefSpecs,
                        env: dstEnv,
                        onProgressLine: progressCallback(for: pushPhase)
                    )
                }
            } else if usesSelectiveRefSync {
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
                    result.failureKind = failureKind(for: error, destinationID: target.id)
                    result.succeeded = false
                    return result
                }
            }

            if plan.policy.content.mirrorsReleases, pushesToCheckBranches {
                targetLog("Skipping release mirroring: check branches leave the destination's releases alone.")
            } else if plan.policy.content.mirrorsReleases, let mirrorReleases {
                targetLog("Mirroring releases...")
                do {
                    try await mirrorReleases(plan, target, sendableTargetLog(targetLog))
                    targetLog("Release mirror complete. ✓")
                } catch {
                    let message = classifyError(error)
                    targetLog("Release mirror error: \(message)")
                    result.error = message
                    result.failureKind = failureKind(for: error, destinationID: target.id)
                    result.succeeded = false
                    return result
                }
            }

            result.succeeded = true
        } catch {
            let message = classifyError(error)
            targetLog(String(localized: "Error: \(message)"))
            result.error = message
            result.failureKind = failureKind(for: error, destinationID: target.id)
            result.succeeded = false
        }

        return result
    }

    private func failureKind(for error: Error, destinationID: UUID) -> MirrorFailureKind {
        if error is DestructivePushError {
            return .destructiveChangeBlocked
        }
        if error is ArchiveError {
            return .localStorage
        }
        if error is GitError, error.localizedDescription.localizedCaseInsensitiveContains("cancel") {
            return .cancelled
        }

        switch SyncFailureClassifier.kind(fromStoredMessage: classifyError(error)) {
        case .authentication:
            return .destinationAuthentication
        case .repositoryNotFound, .pushRejected:
            return .destinationRejected
        case .network:
            return .network
        case .other:
            return .unknown
        }
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
        CredentialRedactor.redact(message)
    }

    private func buildEnv(for auth: AuthConfig) -> [String: String] {
        switch auth {
        case .sshAgent:
            return [:]
        case .sshKey(let path):
            return ["GIT_SSH_COMMAND": GitSSHCommand.usingPrivateKey(at: path)]
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
