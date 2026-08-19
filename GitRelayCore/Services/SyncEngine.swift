import Foundation

enum SyncEvent {
    case started
    case log(String)
    case statusChanged(SyncStatus)
    case completed(SyncRecord)
    case failed(String, SyncRecord)
}

@MainActor
final class SyncEngine {
    private let repo: RepoConfig
    private let runner = GitRunner()
    private var record: SyncRecord

    var onEvent: ((SyncEvent) -> Void)?

    /// Called when `.strict` policy needs an explicit continue/cancel decision.
    /// Return `true` to proceed with the destructive push, `false` to block.
    var confirmDestructivePush: ((DestructivePushPlan, MirrorTarget) async -> Bool)?

    init(repo: RepoConfig) {
        self.repo = repo
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

        do {
            // 1. Clone or fetch from src once
            if MirrorStore.mirrorExists(for: repo.id) {
                log("Fetching from source...")
                try await runner.fetchPrune(mirrorPath: mirrorPath, env: srcEnv)
                log("Fetch complete.")
            } else {
                log("Cloning source (first time)...")
                do {
                    try await runner.cloneMirror(srcURL: srcURL, mirrorPath: mirrorPath, env: srcEnv)
                } catch {
                    try? MirrorStore.deleteMirror(for: repo.id)
                    throw error
                }
                log("Clone complete.")
            }

            guard !enabledTargets.isEmpty else {
                throw SyncEngineError.noEnabledTargets
            }

            // 2. Push to each enabled target independently
            var targetResults: [TargetSyncResult] = []
            for target in enabledTargets {
                let result = await pushToTarget(target, mirrorPath: mirrorPath)
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
                log("Error: \(message)")
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
            log("Error: \(message)")
            record.finishedAt = Date()
            emit(.failed(message, record))
            emit(.statusChanged(.failed(message)))
        }
    }

    func cancel() {
        Task { await runner.cancel() }
    }

    // MARK: - Private

    private func pushToTarget(_ target: MirrorTarget, mirrorPath: String) async -> TargetSyncResult {
        var result = TargetSyncResult(targetID: target.id, targetURL: target.url)
        let rawDstURL = target.url
        let dstURL = authenticatedURL(url: rawDstURL, auth: target.auth)
        let dstEnv = buildEnv(for: target.auth)

        func targetLog(_ line: String) {
            result.logLines.append(line)
            emit(.log("[\(rawDstURL)] \(line)"))
        }

        targetLog("Target: \(rawDstURL)")

        do {
            targetLog("Checking destination...")
            var commitsBefore = 0
            do {
                try await runner.fetchDstRefs(mirrorPath: mirrorPath, dstURL: dstURL, env: dstEnv)
                commitsBefore = (try? await runner.countCommitsAhead(mirrorPath: mirrorPath)) ?? 0
                targetLog("Source is \(commitsBefore) commit(s) ahead of destination.")
            } catch {
                targetLog("Note: Could not read destination refs — first push? (\(error.localizedDescription))")
            }
            result.commitsBefore = commitsBefore

            targetLog("Checking mirror push impact...")
            let plan = try await runner.pushMirrorDryRun(mirrorPath: mirrorPath, dstURL: dstURL, env: dstEnv)
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
            try await runner.pushMirror(mirrorPath: mirrorPath, dstURL: dstURL, env: dstEnv)
            targetLog("Push complete. ✓")
            result.succeeded = true
        } catch {
            let message = classifyError(error)
            targetLog("Error: \(message)")
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

    private func authenticatedURL(url: String, auth: AuthConfig) -> String {
        guard case .httpsToken(let tag) = auth,
              let token = try? KeychainService.loadToken(tag: tag) else { return url }
        guard var components = URLComponents(string: url) else { return url }
        components.user = token
        return components.string ?? url
    }

    private func classifyError(_ error: Error) -> String {
        if let syncError = error as? SyncEngineError {
            return syncError.localizedDescription
        }
        if let destructivePushError = error as? DestructivePushError {
            return destructivePushError.localizedDescription
        }

        let raw = SyncEngine.redactCredentials(error.localizedDescription)
        let lower = raw.lowercased()
        if lower.contains("authentication failed") || lower.contains("permission denied") ||
           lower.contains("could not read username") || lower.contains("invalid username or password") ||
           lower.contains("access denied") {
            return "Authentication failed — check credentials"
        }
        if lower.contains("repository not found") || (lower.contains("not found") && lower.contains("git")) {
            return "Repository not found — check URL"
        }
        if lower.contains("could not resolve host") || lower.contains("connection timed out") ||
           lower.contains("network is unreachable") || lower.contains("ssl certificate") {
            return "Network error — check connectivity"
        }
        if lower.contains("rejected") || lower.contains("non-fast-forward") {
            return "Push rejected — destination has diverged"
        }
        return raw
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

enum SyncEngineError: LocalizedError {
    case noEnabledTargets

    var errorDescription: String? {
        switch self {
        case .noEnabledTargets:
            return "No enabled mirror targets"
        }
    }
}
