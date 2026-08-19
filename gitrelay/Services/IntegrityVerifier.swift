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
        let dstURL = authenticatedURL(url: repo.dstURL, auth: repo.dstAuth)
        let srcEnv = buildEnv(for: repo.srcAuth)
        let dstEnv = buildEnv(for: repo.dstAuth)

        do {
            log("ls-remote 源仓库...")
            let srcSHA = try await runner.lsRemoteTipSHA(url: srcURL, branch: branch, env: srcEnv)
            log("src tip: \(srcSHA?.truncatingSHA ?? "(缺失)")")

            log("ls-remote 目标仓库...")
            let dstSHA = try await runner.lsRemoteTipSHA(url: dstURL, branch: branch, env: dstEnv)
            log("dst tip: \(dstSHA?.truncatingSHA ?? "(缺失)")")

            var srcTree: String?
            var dstTree: String?

            if let srcSHA, let dstSHA, srcSHA != dstSHA {
                log("commit SHA 不一致，拉取对象以比较 tree hash...")
                let workPath = try await prepareWorkRepo()
                srcTree = try await fetchTreeHash(
                    workPath: workPath,
                    remoteURL: srcURL,
                    commitSHA: srcSHA,
                    env: srcEnv,
                    label: "src"
                )
                dstTree = try await fetchTreeHash(
                    workPath: workPath,
                    remoteURL: dstURL,
                    commitSHA: dstSHA,
                    env: dstEnv,
                    label: "dst"
                )
            }

            let decision = VerificationDecision.decide(
                branch: branch,
                srcCommitSHA: srcSHA,
                dstCommitSHA: dstSHA,
                srcTreeHash: srcTree,
                dstTreeHash: dstTree
            )

            record.finishedAt = Date()
            switch decision {
            case .matched(let reason):
                record.succeeded = true
                switch reason {
                case .identicalCommitSHA:
                    log("两侧 tip 一致 — 校验通过。")
                case .identicalTreeHash:
                    log("commit SHA 不同但 tree hash 一致 — 校验通过。")
                }
                emit(.completed(decision, record))

            case .diverged(let detail):
                record.succeeded = false
                log("⚠ 检测到内容分歧: \(detail.summary)")
                log("  src tree: \(detail.srcTreeHash.truncatingSHA)")
                log("  dst tree: \(detail.dstTreeHash.truncatingSHA)")
                emit(.completed(decision, record))

            case .inconclusive(let message):
                record.succeeded = false
                let redacted = SyncEngine.redactCredentials(message)
                log("无法判定: \(redacted)")
                emit(.failed(redacted, record))
            }

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

    private func prepareWorkRepo() async throws -> String {
        if MirrorStore.mirrorExists(for: repo.id) {
            return MirrorStore.mirrorPath(for: repo.id).path
        }
        // Do not seed the real mirror path — SyncEngine treats HEAD as a full mirror clone.
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
        label: String
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
