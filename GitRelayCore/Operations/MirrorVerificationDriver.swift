import Foundation

nonisolated enum MirrorVerificationDriverEvent: Sendable {
    case started
    case log(String)
    case finished(MirrorRunRecord)
}

@MainActor
protocol MirrorVerificationDriving: AnyObject {
    var onEvent: ((MirrorVerificationDriverEvent) -> Void)? { get set }

    func run() async
    func cancel()
}

/// Verifies one branch from the source against every enabled Git destination.
/// Archive destinations are intentionally excluded because they do not expose refs.
@MainActor
final class GitMirrorVerificationDriver: MirrorVerificationDriving {
    var onEvent: ((MirrorVerificationDriverEvent) -> Void)?

    private let plan: MirrorPlan
    private let runner: GitRunner
    private let mirrorRootDirectory: URL
    private let scratchRootDirectory: URL
    private var isCancelled = false
    private var startedAt = Date()
    private var logLines: [String] = []

    init(
        plan: MirrorPlan,
        runner: GitRunner = GitRunner(),
        mirrorRootDirectory: URL = Constants.mirrorCacheDirectory,
        scratchRootDirectory: URL = Constants.verificationScratchDirectory
    ) {
        self.plan = plan
        self.runner = runner
        self.mirrorRootDirectory = mirrorRootDirectory
        self.scratchRootDirectory = scratchRootDirectory
    }

    func run() async {
        startedAt = Date()
        logLines = []
        onEvent?(.started)

        guard !isCancelled else {
            finishCancelled()
            return
        }

        let branch = plan.policy.verification.branch
        log("Integrity verification started for branch \(branch).")
        let destinations = plan.enabledDestinations.compactMap { destination -> (MirrorDestination, GitEndpoint)? in
            guard case .git(let endpoint) = destination.location else { return nil }
            return (destination, endpoint)
        }

        guard !destinations.isEmpty else {
            let message = "No enabled Git destinations are available for verification."
            finish(
                outcome: .failed,
                failure: MirrorFailureSummary(kind: .unknown, message: message),
                results: []
            )
            return
        }

        if destinations.count < plan.enabledDestinations.count {
            log("Skipped \(plan.enabledDestinations.count - destinations.count) archive destinations.")
        }

        let sourceURL = authenticatedURL(for: plan.source)
        let sourceEnvironment = environment(for: plan.source.auth)
        let sourceSHA: String?
        do {
            sourceSHA = try await runner.lsRemoteTipSHA(
                url: sourceURL,
                branch: branch,
                env: sourceEnvironment
            )
        } catch GitError.cancelled {
            finishCancelled()
            return
        } catch {
            let failure = makeFailure(error: error, destinationID: nil)
            log("Source verification failed: \(failure.message)")
            finish(outcome: .failed, failure: failure, results: [])
            return
        }

        var results: [MirrorDestinationVerificationResult] = []
        for (destination, endpoint) in destinations {
            if isCancelled {
                finishCancelled(results: results)
                return
            }

            let completedAt: Date
            do {
                let destinationURL = authenticatedURL(for: endpoint)
                let destinationEnvironment = environment(for: endpoint.auth)
                let destinationSHA = try await runner.lsRemoteTipSHA(
                    url: destinationURL,
                    branch: branch,
                    env: destinationEnvironment
                )

                var sourceTree: String?
                var destinationTree: String?
                if let sourceSHA, let destinationSHA, sourceSHA != destinationSHA {
                    let workPath = try await prepareWorkRepository()
                    sourceTree = try await fetchTreeHash(
                        workPath: workPath,
                        endpoint: plan.source,
                        commitSHA: sourceSHA
                    )
                    destinationTree = try await fetchTreeHash(
                        workPath: workPath,
                        endpoint: endpoint,
                        commitSHA: destinationSHA
                    )
                }

                let decision = VerificationDecision.decide(
                    branch: branch,
                    srcCommitSHA: sourceSHA,
                    dstCommitSHA: destinationSHA,
                    srcTreeHash: sourceTree,
                    dstTreeHash: destinationTree
                )
                completedAt = Date()
                let integrity = Self.integrity(from: decision)
                results.append(
                    MirrorDestinationVerificationResult(
                        destinationID: destination.id,
                        completedAt: completedAt,
                        integrity: integrity,
                        failure: nil
                    )
                )
                log("Destination \(destination.id.uuidString) verification: \(Self.logLabel(for: integrity)).")
            } catch GitError.cancelled {
                finishCancelled(results: results)
                return
            } catch {
                completedAt = Date()
                let failure = makeFailure(error: error, destinationID: destination.id)
                results.append(
                    MirrorDestinationVerificationResult(
                        destinationID: destination.id,
                        completedAt: completedAt,
                        integrity: .inconclusive(failure.message),
                        failure: failure
                    )
                )
                log("Destination \(destination.id.uuidString) verification failed: \(failure.message)")
            }
        }

        let verifiedCount = results.filter { $0.integrity == .verified }.count
        let outcome: MirrorRunOutcome
        if verifiedCount == results.count {
            outcome = .succeeded
        } else if verifiedCount > 0 {
            outcome = .partiallySucceeded
        } else {
            outcome = .failed
        }
        finish(
            outcome: outcome,
            failure: results.compactMap(\.failure).first,
            results: results
        )
    }

    func cancel() {
        isCancelled = true
        Task { await runner.cancel() }
    }

    private func prepareWorkRepository() async throws -> String {
        if MirrorStore.mirrorExists(for: plan.id, rootDirectory: mirrorRootDirectory) {
            return MirrorStore.mirrorPath(for: plan.id, rootDirectory: mirrorRootDirectory).path
        }
        let scratch = scratchRootDirectory.appendingPathComponent(plan.id.uuidString)
        try await runner.ensureBareRepo(at: scratch.path)
        return scratch.path
    }

    private func fetchTreeHash(
        workPath: String,
        endpoint: GitEndpoint,
        commitSHA: String
    ) async throws -> String {
        try await runner.fetchCommit(
            repoPath: workPath,
            remoteURL: authenticatedURL(for: endpoint),
            commitSHA: commitSHA,
            env: environment(for: endpoint.auth)
        )
        return try await runner.treeHash(repoPath: workPath, commitSHA: commitSHA)
    }

    private func authenticatedURL(for endpoint: GitEndpoint) -> String {
        guard case .httpsToken(let tag) = endpoint.auth,
              let token = try? KeychainService.loadToken(tag: tag),
              var components = URLComponents(string: endpoint.url)
        else {
            return endpoint.url
        }
        components.user = token
        return components.string ?? endpoint.url
    }

    private func environment(for auth: AuthConfig) -> [String: String] {
        switch auth {
        case .sshAgent:
            [:]
        case .sshKey(let path):
            ["GIT_SSH_COMMAND": GitSSHCommand.usingPrivateKey(at: path)]
        case .httpsToken:
            ["GIT_TERMINAL_PROMPT": "0"]
        }
    }

    private func makeFailure(error: Error, destinationID: UUID?) -> MirrorFailureSummary {
        let message = SyncEngine.redactCredentials(error.localizedDescription)
        let kind: MirrorFailureKind
        switch SyncFailureClassifier.kind(fromStoredMessage: message) {
        case .authentication:
            kind = destinationID == nil ? .sourceAuthentication : .destinationAuthentication
        case .repositoryNotFound:
            kind = destinationID == nil ? .sourceUnavailable : .destinationRejected
        case .network:
            kind = .network
        case .pushRejected:
            kind = .destinationRejected
        case .other:
            kind = .unknown
        }
        return MirrorFailureSummary(
            kind: kind,
            message: message,
            destinationID: destinationID
        )
    }

    private func finishCancelled(results: [MirrorDestinationVerificationResult] = []) {
        let failure = MirrorFailureSummary(kind: .cancelled, message: "Cancelled")
        finish(outcome: .cancelled, failure: failure, results: results)
    }

    private func finish(
        outcome: MirrorRunOutcome,
        failure: MirrorFailureSummary?,
        results: [MirrorDestinationVerificationResult]
    ) {
        let finishedAt = Date()
        let record = MirrorRunRecord(
            mirrorID: plan.id,
            kind: .verification,
            startedAt: startedAt,
            finishedAt: finishedAt,
            outcome: outcome,
            failure: failure,
            logLines: logLines,
            verificationResults: results
        )
        onEvent?(.finished(record))
    }

    private func log(_ line: String) {
        let safeLine = SyncEngine.redactCredentials(line)
        logLines.append(safeLine)
        onEvent?(.log(safeLine))
    }

    private static func integrity(from decision: VerificationDecision) -> MirrorIntegrityState {
        switch decision {
        case .matched:
            .verified
        case .diverged(let detail):
            .diverged(detail.summary)
        case .inconclusive(let message):
            .inconclusive(SyncEngine.redactCredentials(message))
        }
    }

    private static func logLabel(for integrity: MirrorIntegrityState) -> String {
        switch integrity {
        case .unknown:
            "unknown"
        case .verified:
            "verified"
        case .diverged:
            "diverged"
        case .inconclusive:
            "inconclusive"
        }
    }
}
