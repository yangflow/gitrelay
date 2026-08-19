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
        log("完整性校验开始（分支: \(branch)）...")

        let srcURL = authenticatedURL(url: repo.srcURL, auth: repo.srcAuth)
        let srcEnv = buildEnv(for: repo.srcAuth)
        let enabledTargets = repo.enabledTargets

        guard !enabledTargets.isEmpty else {
            let message = SyncEngineError.noEnabledTargets.localizedDescription ?? "No enabled mirror targets"
            log("错误: \(message)")
            record.finishedAt = Date()
            emit(.failed(message, record))
            return
        }

        do {
            log("ls-remote 源仓库...")
            let srcSHA = try await runner.lsRemoteTipSHA(url: srcURL, branch: branch, env: srcEnv)
            log("src tip: \(srcSHA?.truncatingSHA ?? "(缺失)")")

            var divergedDetails: [VerificationDecision.Detail] = []
            var inconclusiveMessages: [String] = []
            var matchedCount = 0

            for target in enabledTargets {
                var targetResult = TargetSyncResult(targetID: target.id, targetURL: target.url)
                let dstURL = authenticatedURL(url: target.url, auth: target.auth)
                let dstEnv = buildEnv(for: target.auth)

                func targetLog(_ line: String) {
                    targetResult.logLines.append(line)
                    emit(.log("[\(target.url)] \(line)"))
                }

                targetLog("ls-remote 目标仓库...")
                let dstSHA = try await runner.lsRemoteTipSHA(url: dstURL, branch: branch, env: dstEnv)
                targetLog("dst tip: \(dstSHA?.truncatingSHA ?? "(缺失)")")

                var srcTree: String?
                var dstTree: String?

                if let srcSHA, let dstSHA, srcSHA != dstSHA {
                    targetLog("commit SHA 不一致，拉取对象以比较 tree hash...")
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
                        targetLog("两侧 tip 一致 — 校验通过。")
                    case .identicalTreeHash:
                        targetLog("commit SHA 不同但 tree hash 一致 — 校验通过。")
                    }
                    matchedCount += 1

                case .diverged(let detail):
                    targetResult.succeeded = false
                    targetResult.error = detail.summary
                    targetLog("⚠ 检测到内容分歧: \(detail.summary)")
                    targetLog("  src tree: \(detail.srcTreeHash.truncatingSHA)")
                    targetLog("  dst tree: \(detail.dstTreeHash.truncatingSHA)")
                    divergedDetails.append(detail)

                case .inconclusive(let message):
                    targetResult.succeeded = false
                    let redacted = SyncEngine.redactCredentials(message)
                    targetResult.error = redacted
                    targetLog("无法判定: \(redacted)")
                    inconclusiveMessages.append("\(target.url): \(redacted)")
                }

                record.targetResults.append(targetResult)
            }

            record.finishedAt = Date()

            if let firstDiverged = divergedDetails.first {
                record.succeeded = false
                let summary = multiTargetDivergenceSummary(details: divergedDetails)
                log("⚠ 检测到内容分歧: \(summary)")
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
                log("无法判定: \(message)")
                emit(.failed(message, record))
                return
            }

            record.succeeded = matchedCount == enabledTargets.count
            log("全部 \(matchedCount) 个目标校验通过。")
            emit(.completed(.matched(reason: .identicalCommitSHA), record))

        } catch GitError.cancelled {
            log("完整性校验已取消。")
            record.finishedAt = Date()
            emit(.failed("Cancelled", record))

        } catch {
            let message = SyncEngine.redactCredentials(error.localizedDescription)
            log("错误: \(message)")
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
        return "\(details.count) 个目标内容分歧: \(details[0].summary)"
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
        log("拉取 \(label) commit \(commitSHA.truncatingSHA)...")
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
