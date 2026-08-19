import Foundation

enum IntegrityVerifyEvent {
    case started
    case log(String)
    case completed(VerificationDecision, SyncRecord)
    case failed(String, SyncRecord)
}

/// One-way mirror integrity check: ls-remote tips, then tree-hash compare when SHAs differ.
@MainActor
final class IntegrityVerifier {
    private let repo: RepoConfig
    private let runner: GitRunner
    private var record: SyncRecord

    var onEvent: ((IntegrityVerifyEvent) -> Void)?

    init(repo: RepoConfig, runner: GitRunner = GitRunner()) {
        self.repo = repo
        self.runner = runner
        self.record = SyncRecord(repoID: repo.id)
    }

    func run() async {
        emit(.started)
        let branch = RepoConfig.normalizedBranch(repo.defaultBranch)
        log(String(localized: "Integrity verification started (branch: \(branch))..."))

        let srcURL = authenticatedURL(url: repo.srcURL, auth: repo.srcAuth)
        let srcEnv = buildEnv(for: repo.srcAuth)
        let enabledTargets = repo.enabledTargets
        let verifiableTargets = enabledTargets.filter { $0.kind == .gitRemote }

        guard !verifiableTargets.isEmpty else {
            let message = enabledTargets.isEmpty
                ? (SyncEngineError.noEnabledTargets.localizedDescription ?? "No enabled mirror targets")
                : "No git remote targets to verify (filesystem archive targets skipped)"
            log(String(localized: "Error: \(message)"))
            record.finishedAt = Date()
            emit(.failed(message, record))
            return
        }

        if verifiableTargets.count < enabledTargets.count {
            log(String(localized: "Skipped \(enabledTargets.count - verifiableTargets.count) filesystem archive targets."))
        }

        do {
            log(String(localized: "Running ls-remote on source repository..."))
            let srcSHA = try await runner.lsRemoteTipSHA(url: srcURL, branch: branch, env: srcEnv)
            log("src tip: \(srcSHA?.truncatingSHA ?? "(missing)")")

            var divergedDetails: [VerificationDecision.Detail] = []
            var inconclusiveMessages: [String] = []
            var matchedCount = 0

            for target in verifiableTargets {
                var targetResult = TargetSyncResult(targetID: target.id, targetURL: target.displayLabel)
                let dstURL = authenticatedURL(url: target.url, auth: target.auth)
                let dstEnv = buildEnv(for: target.auth)

                func targetLog(_ line: String) {
                    targetResult.logLines.append(line)
                    emit(.log("[\(target.displayLabel)] \(line)"))
                }

                targetLog(String(localized: "Running ls-remote on target repository..."))
                let dstSHA = try await runner.lsRemoteTipSHA(url: dstURL, branch: branch, env: dstEnv)
                targetLog("dst tip: \(dstSHA?.truncatingSHA ?? "(missing)")")

                var srcTree: String?
                var dstTree: String?

                if let srcSHA, let dstSHA, srcSHA != dstSHA {
                    targetLog(String(localized: "Commit SHAs differ; fetching objects to compare tree hashes..."))
                    let workPath = try await prepareWorkRepo()
                    srcTree = try await fetchTreeHash(
                        workPath: workPath,
                        remoteURL: srcURL,
                        commitSHA: srcSHA,
                        env: srcEnv,
                        label: "src",
                        log: targetLog
                    )
                    dstTree = try await fetchTreeHash(
                        workPath: workPath,
                        remoteURL: dstURL,
                        commitSHA: dstSHA,
                        env: dstEnv,
                        label: "dst",
                        log: targetLog
                    )
                }

                let decision = VerificationDecision.decide(
                    branch: branch,
                    srcCommitSHA: srcSHA,
                    dstCommitSHA: dstSHA,
                    srcTreeHash: srcTree,
                    dstTreeHash: dstTree
                )

                switch decision {
                case .matched(let reason):
                    targetResult.succeeded = true
                    switch reason {
                    case .identicalCommitSHA:
                        targetLog(String(localized: "Tips match — verification passed."))
                    case .identicalTreeHash:
                        targetLog(String(localized: "Commit SHAs differ but tree hashes match — verification passed."))
                    }
                    matchedCount += 1

                case .diverged(let detail):
                    targetResult.succeeded = false
                    targetResult.error = detail.summary
                    targetLog(String(localized: "⚠ Content divergence detected: \(detail.summary)"))
                    targetLog("  src tree: \(detail.srcTreeHash.truncatingSHA)")
                    targetLog("  dst tree: \(detail.dstTreeHash.truncatingSHA)")
                    divergedDetails.append(detail)

                case .inconclusive(let message):
                    targetResult.succeeded = false
                    let redacted = SyncEngine.redactCredentials(message)
                    targetResult.error = redacted
                    targetLog(String(localized: "Inconclusive: \(redacted)"))
                    inconclusiveMessages.append("\(target.displayLabel): \(redacted)")
                }

                record.targetResults.append(targetResult)
            }

            record.finishedAt = Date()

            if let firstDiverged = divergedDetails.first {
                record.succeeded = false
                let summary = multiTargetDivergenceSummary(details: divergedDetails)
                log(String(localized: "⚠ Content divergence detected: \(summary)"))
                var detail = firstDiverged
                if divergedDetails.count > 1 {
                    detail.summaryOverride = summary
                }
                emit(.completed(.diverged(detail), record))
                return
            }

            if !inconclusiveMessages.isEmpty {
                record.succeeded = false
                let message = inconclusiveMessages.joined(separator: "; ")
                log(String(localized: "Inconclusive: \(message)"))
                emit(.failed(message, record))
                return
            }

            record.succeeded = matchedCount == verifiableTargets.count
            log(String(localized: "All \(matchedCount) targets passed verification."))
            emit(.completed(.matched(reason: .identicalCommitSHA), record))

        } catch GitError.cancelled {
            log(String(localized: "Integrity verification canceled."))
            record.finishedAt = Date()
            emit(.failed("Cancelled", record))

        } catch {
            let message = SyncEngine.redactCredentials(error.localizedDescription)
            log(String(localized: "Error: \(message)"))
            record.finishedAt = Date()
            emit(.failed(message, record))
        }
    }

    func cancel() {
        Task { await runner.cancel() }
    }

    // MARK: - Private

    private func multiTargetDivergenceSummary(details: [VerificationDecision.Detail]) -> String {
        guard details.count > 1 else { return details[0].summary }
        return String(localized: "\(details.count) targets have content divergence: \(details[0].summary)")
    }

    private func prepareWorkRepo() async throws -> String {
        if MirrorStore.mirrorExists(for: repo.id) {
            return MirrorStore.mirrorPath(for: repo.id).path
        }
        let scratch = Constants.baseDirectory
            .appendingPathComponent("verify-scratch")
            .appendingPathComponent(repo.id.uuidString)
        try await runner.ensureBareRepo(at: scratch.path)
        return scratch.path
    }

    private func fetchTreeHash(
        workPath: String,
        remoteURL: String,
        commitSHA: String,
        env: [String: String],
        label: String,
        log: (String) -> Void
    ) async throws -> String {
        log(String(localized: "Fetching \(label) commit \(commitSHA.truncatingSHA)..."))
        try await runner.fetchCommit(
            repoPath: workPath,
            remoteURL: remoteURL,
            commitSHA: commitSHA,
            env: env
        )
        let tree = try await runner.treeHash(repoPath: workPath, commitSHA: commitSHA)
        log("\(label) tree: \(tree.truncatingSHA)")
        return tree
    }

    private func log(_ line: String) {
        record.logLines.append(line)
        emit(.log(line))
    }

    private func emit(_ event: IntegrityVerifyEvent) {
        onEvent?(event)
    }

    private func authenticatedURL(url: String, auth: AuthConfig) -> String {
        guard case .httpsToken(let tag) = auth,
              let token = try? KeychainService.loadToken(tag: tag) else { return url }
        guard var components = URLComponents(string: url) else { return url }
        components.user = token
        return components.string ?? url
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
