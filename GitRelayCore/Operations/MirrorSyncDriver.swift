import Foundation

nonisolated enum MirrorSyncDriverEvent: Sendable {
    case started
    case phase(SyncPhase)
    case log(String)
    case finished(MirrorRunRecord)
}

/// Execution boundary shared by the product and application layers.
@MainActor
protocol MirrorSyncDriving: AnyObject {
    var onEvent: ((MirrorSyncDriverEvent) -> Void)? { get set }
    var confirmDestructivePush: (
        (DestructivePushPlan, MirrorDestination) async -> DestructivePushDecision
    )? { get set }
    var mirrorReleases: (
        (
            MirrorPlan,
            MirrorDestination,
            @escaping @Sendable (String) -> Void
        ) async throws -> Void
    )? { get set }

    func run() async
    func cancel()
}

/// Native driver. MirrorPlan remains the execution source of truth all the way
/// into SyncEngine; persisted repository-list configuration is never consulted.
@MainActor
final class MirrorSyncDriver: MirrorSyncDriving {
    var onEvent: ((MirrorSyncDriverEvent) -> Void)?
    var confirmDestructivePush: (
        (DestructivePushPlan, MirrorDestination) async -> DestructivePushDecision
    )?
    var mirrorReleases: (
        (
            MirrorPlan,
            MirrorDestination,
            @escaping @Sendable (String) -> Void
        ) async throws -> Void
    )?

    private let plan: MirrorPlan
    private let engine: SyncEngine

    init(
        plan: MirrorPlan,
        retryPolicy: GitRetryPolicy = .default,
        mirrorRootDirectory: URL = Constants.mirrorCacheDirectory,
        runner: GitRunner? = nil,
        archiveService: FilesystemArchiveService? = nil,
        lfsCommandRunner: (any LFSCommandRunning)? = nil
    ) {
        self.plan = plan
        let runner = runner ?? GitRunner()
        self.engine = SyncEngine(
            plan: plan,
            retryPolicy: retryPolicy,
            mirrorRootDirectory: mirrorRootDirectory,
            runner: runner,
            archiveService: archiveService,
            lfsCommandRunner: lfsCommandRunner ?? runner
        )
    }

    func run() async {
        engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
        engine.confirmDestructivePush = { [weak self] destructivePlan, destination in
            guard let self, let confirmDestructivePush = self.confirmDestructivePush else {
                return .cancel
            }
            return await confirmDestructivePush(destructivePlan, destination)
        }
        engine.mirrorReleases = { [weak self] _, destination, log in
            guard let self,
                  let mirrorReleases = self.mirrorReleases
            else {
                return
            }
            try await mirrorReleases(self.plan, destination, log)
        }
        await engine.run()
    }

    func cancel() {
        engine.cancel()
    }

    private func handle(_ event: SyncEvent) {
        switch event {
        case .started:
            onEvent?(.started)
        case .phase(let phase):
            onEvent?(.phase(phase))
        case .log(let line):
            onEvent?(.log(SyncEngine.redactCredentials(line)))
        case .statusChanged:
            break
        case .completed(let record):
            onEvent?(.finished(Self.makeRunRecord(from: record, failureMessage: nil)))
        case .failed(let message, let record):
            onEvent?(.finished(Self.makeRunRecord(from: record, failureMessage: message)))
        }
    }

    static func makeRunRecord(
        from record: SyncRecord,
        failureMessage: String?
    ) -> MirrorRunRecord {
        let finishedAt = record.finishedAt ?? Date()
        let wasCancelled = failureMessage?.localizedCaseInsensitiveContains("cancelled") == true
        let succeededCount = record.targetResults.filter(\.succeeded).count
        let outcome: MirrorRunOutcome
        if wasCancelled {
            outcome = .cancelled
        } else if record.succeeded {
            outcome = .succeeded
        } else if succeededCount > 0 {
            outcome = .partiallySucceeded
        } else {
            outcome = .failed
        }

        let destinationResults = record.targetResults.map { result in
            let failure = result.error.map {
                MirrorFailureSummary(
                    kind: result.failureKind ?? inferredFailureKind(
                        message: $0,
                        destinationID: result.targetID
                    ),
                    message: $0,
                    failedAt: finishedAt,
                    destinationID: result.targetID
                )
            }
            return MirrorDestinationRunResult(
                destinationID: result.targetID,
                succeeded: result.succeeded,
                completedAt: finishedAt,
                failure: failure
            )
        }
        let targetLogs = record.targetResults.flatMap { result in
            result.logLines.map { "[\(result.targetURL)] \($0)" }
        }
        let failure = failureMessage.map { message in
            if wasCancelled {
                return makeFailure(message: message, failedAt: finishedAt, destinationID: nil)
            }
            let failedDestinations = destinationResults.filter { !$0.succeeded }
            if let destinationFailure = failedDestinations.compactMap(\.failure).first {
                return MirrorFailureSummary(
                    kind: destinationFailure.kind,
                    message: message,
                    failedAt: finishedAt,
                    destinationID: failedDestinations.count == 1
                        ? destinationFailure.destinationID
                        : nil
                )
            }
            return makeFailure(message: message, failedAt: finishedAt, destinationID: nil)
        }

        return MirrorRunRecord(
            id: record.id,
            mirrorID: record.repoID,
            startedAt: record.startedAt,
            finishedAt: finishedAt,
            outcome: outcome,
            failure: failure,
            logLines: record.logLines + targetLogs,
            destinationResults: destinationResults
        )
    }

    private static func makeFailure(
        message: String,
        failedAt: Date,
        destinationID: UUID?
    ) -> MirrorFailureSummary {
        let safeMessage = SyncEngine.redactCredentials(message)
        let kind = inferredFailureKind(message: safeMessage, destinationID: destinationID)
        return MirrorFailureSummary(
            kind: kind,
            message: safeMessage,
            failedAt: failedAt,
            destinationID: destinationID
        )
    }

    private static func inferredFailureKind(
        message safeMessage: String,
        destinationID: UUID?
    ) -> MirrorFailureKind {
        if safeMessage.localizedCaseInsensitiveContains("cancelled") {
            return .cancelled
        } else if safeMessage.localizedCaseInsensitiveContains("destructive") ||
                    safeMessage.localizedCaseInsensitiveContains("blocked") {
            return .destructiveChangeBlocked
        } else {
            switch SyncFailureClassifier.kind(fromStoredMessage: safeMessage) {
            case .authentication:
                return destinationID == nil ? .sourceAuthentication : .destinationAuthentication
            case .repositoryNotFound:
                return destinationID == nil ? .sourceUnavailable : .destinationRejected
            case .network:
                return .network
            case .pushRejected:
                return .destinationRejected
            case .other:
                return .unknown
            }
        }
    }
}
