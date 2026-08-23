import Foundation
import Observation

/// Owns manual sync/verification execution and all ephemeral operation state.
/// Scheduling may request work, but it does not own engines, queue admission,
/// cancellation, or destructive-push decisions.
@MainActor
@Observable
final class MirrorOperationsController {
    enum SyncCompletion: Equatable {
        case succeeded
        case failed(String)
    }

    let library: MirrorLibraryModel

    private(set) var statuses: [UUID: SyncStatus] = [:]
    private(set) var records: [UUID: [SyncRecord]] = [:]
    private(set) var syncPhases: [UUID: SyncPhase] = [:]
    private(set) var liveSyncLogLines: [UUID: String] = [:]
    private(set) var inProgressSyncIDs: Set<UUID> = []
    private(set) var inProgressVerifyIDs: Set<UUID> = []
    private(set) var pendingDestructiveConfirmations: [DestructivePushConfirmationRequest] = []

    /// Test seam: admitted syncs retain their slots without launching Git.
    var suspendSyncEngineForTesting = false

    @ObservationIgnored
    var retryPolicyProvider: () -> GitRetryPolicy = { .default }
    @ObservationIgnored
    var onStateChange: () -> Void = {}
    @ObservationIgnored
    var onError: (String) -> Void = { _ in }
    @ObservationIgnored
    var onCredentialsRequired: (UUID, String) -> Void = { _, _ in }
    @ObservationIgnored
    var onSyncSettled: (UUID) -> Void = { _ in }
    @ObservationIgnored
    var onSyncCompletion: (UUID, SyncCompletion) -> Void = { _, _ in }
    @ObservationIgnored
    var onDestructiveConfirmationRequested: () -> Void = {}

    @ObservationIgnored
    private let concurrencyGate: SyncConcurrencyGate
    @ObservationIgnored
    private let releaseMirrorService: ReleaseMirrorService
    @ObservationIgnored
    private let credentialProbe: CredentialProbe
    @ObservationIgnored
    private var activeSyncOperations: [UUID: MirrorSyncOperation] = [:]
    @ObservationIgnored
    private var activeVerifiers: [UUID: MirrorVerificationOperation] = [:]
    @ObservationIgnored
    private var operationEpochs: [UUID: Int] = [:]

    init(
        library: MirrorLibraryModel,
        maxConcurrentSyncs: Int = SyncConcurrencyGate.defaultMaxConcurrent,
        releaseMirrorService: ReleaseMirrorService? = nil,
        credentialProbe: CredentialProbe = .live
    ) {
        self.library = library
        self.concurrencyGate = SyncConcurrencyGate(maxConcurrent: maxConcurrentSyncs)
        self.releaseMirrorService = releaseMirrorService ?? ReleaseMirrorService()
        self.credentialProbe = credentialProbe
        resetStateFromLibrary()
    }

    var presentedDestructiveConfirmation: DestructivePushConfirmationRequest? {
        pendingDestructiveConfirmations.first
    }

    var queueEntries: [MirrorQueueEntry] {
        MirrorQueueProjection.entries(
            repos: library.mirrors,
            statuses: statuses,
            syncPhases: syncPhases
        )
    }

    func isQueued(_ mirrorID: UUID) -> Bool {
        concurrencyGate.isQueued(mirrorID)
    }

    func register(_ mirror: MirrorSnapshot) {
        statuses[mirror.id] = initialStatus(for: mirror)
        records[mirror.id] = []
    }

    func update(_ mirror: MirrorSnapshot) {
        if mirror.isDiverged {
            statuses[mirror.id] = .diverged(
                mirror.divergedDetail ?? String.loc("Content divergence")
            )
        } else if case .diverged = statuses[mirror.id] {
            statuses[mirror.id] = mirror.lastSyncError.map(SyncStatus.failed) ?? .unknown
        } else if mirror.needsCredentials {
            statuses[mirror.id] = .failed(MirrorCredentialGate.missingCredentialsMessage)
        } else if case .failed(let message) = statuses[mirror.id],
                  message == MirrorCredentialGate.missingCredentialsMessage {
            statuses[mirror.id] = mirror.lastSyncError.map(SyncStatus.failed) ?? .unknown
        }
    }

    func unregister(mirrorID: UUID) {
        invalidateOperation(mirrorID: mirrorID)
        if concurrencyGate.cancelQueued(mirrorID) {
            onSyncSettled(mirrorID)
        }
        activeSyncOperations[mirrorID]?.cancel()
        activeVerifiers[mirrorID]?.cancel()
        activeSyncOperations.removeValue(forKey: mirrorID)
        activeVerifiers.removeValue(forKey: mirrorID)
        inProgressSyncIDs.remove(mirrorID)
        inProgressVerifyIDs.remove(mirrorID)
        syncPhases.removeValue(forKey: mirrorID)
        liveSyncLogLines.removeValue(forKey: mirrorID)
        denyPendingDestructiveConfirmation(for: mirrorID)
        if let next = concurrencyGate.finishActive(mirrorID) {
            promoteQueuedSync(mirrorID: next)
        }
        statuses.removeValue(forKey: mirrorID)
        records.removeValue(forKey: mirrorID)
        onStateChange()
    }

    /// Cancels the old generation and rebuilds runtime state after a library
    /// replacement. Returns the IDs whose external notification state should
    /// also be cleared by the composition layer.
    @discardableResult
    func resetForCurrentLibrary() -> Set<UUID> {
        let trackedIDs = Set(statuses.keys)
            .union(inProgressSyncIDs)
            .union(inProgressVerifyIDs)
        for id in trackedIDs {
            invalidateOperation(mirrorID: id)
            activeSyncOperations[id]?.cancel()
            activeVerifiers[id]?.cancel()
            denyPendingDestructiveConfirmation(for: id)
        }
        activeSyncOperations.removeAll()
        activeVerifiers.removeAll()
        concurrencyGate.reset()
        resetStateFromLibrary()
        onStateChange()
        return trackedIDs
    }

    func triggerSync(mirrorID: UUID) {
        guard !inProgressSyncIDs.contains(mirrorID),
              !concurrencyGate.isQueued(mirrorID),
              !inProgressVerifyIDs.contains(mirrorID),
              let mirror = library.mirror(id: mirrorID) else { return }

        if mirror.needsCredentials || MirrorCredentialGate.needsCredentials(
            for: mirror.plan,
            probe: credentialProbe
        ) {
            let message = MirrorCredentialGate.missingCredentialsMessage
            library.markNeedsCredentials(true, mirrorID: mirrorID)
            statuses[mirrorID] = .failed(message)
            onCredentialsRequired(mirrorID, message)
            onStateChange()
            return
        }

        switch concurrencyGate.request(mirrorID) {
        case .alreadyTracked:
            return
        case .enqueued:
            statuses[mirrorID] = .queued
            onStateChange()
        case .beginImmediately:
            startAdmittedSync(mirror: mirror)
        }
    }

    func triggerSyncAll() {
        library.mirrors.forEach { triggerSync(mirrorID: $0.id) }
    }

    func cancelSync(mirrorID: UUID) {
        if concurrencyGate.cancelQueued(mirrorID) {
            onSyncSettled(mirrorID)
            statuses[mirrorID] = library.mirror(id: mirrorID).map(initialStatus) ?? nil
            onStateChange()
            return
        }

        denyPendingDestructiveConfirmation(for: mirrorID)
        if suspendSyncEngineForTesting, inProgressSyncIDs.contains(mirrorID) {
            finishSync(mirrorID: mirrorID)
            statuses[mirrorID] = library.mirror(id: mirrorID).map(initialStatus) ?? nil
            onStateChange()
            return
        }
        activeSyncOperations[mirrorID]?.cancel()
    }

    func triggerVerify(mirrorID: UUID) {
        guard !inProgressSyncIDs.contains(mirrorID),
              !concurrencyGate.isQueued(mirrorID),
              !inProgressVerifyIDs.contains(mirrorID),
              let mirror = library.mirror(id: mirrorID) else { return }
        startVerify(mirror: mirror)
    }

    func cancelVerify(mirrorID: UUID) {
        activeVerifiers[mirrorID]?.cancel()
    }

    func updateMaxConcurrentSyncs(_ value: Int) {
        for mirrorID in concurrencyGate.updateMaxConcurrent(value) {
            promoteQueuedSync(mirrorID: mirrorID)
        }
    }

    func resolvePendingDestructivePush(_ decision: DestructivePushDecision) {
        guard !pendingDestructiveConfirmations.isEmpty else { return }
        pendingDestructiveConfirmations.removeFirst().respond(decision)
    }

    func activity(mirrorID: UUID) -> MirrorActivityState {
        if inProgressVerifyIDs.contains(mirrorID) {
            return .verifying(progress: nil)
        }
        if inProgressSyncIDs.contains(mirrorID) {
            return .synchronizing(
                phase: syncPhases[mirrorID] ?? SyncPhase(.fetchingSource),
                progress: nil
            )
        }
        if let position = queueEntries.firstIndex(where: { $0.id == mirrorID }) {
            return .queued(position: position + 1)
        }
        return .idle
    }

    private func startAdmittedSync(mirror: MirrorSnapshot) {
        let mirrorID = mirror.id
        let epoch = beginOperation(mirrorID: mirrorID)
        inProgressSyncIDs.insert(mirrorID)
        statuses[mirrorID] = .syncing
        syncPhases[mirrorID] = SyncPhase(.fetchingSource)
        liveSyncLogLines.removeValue(forKey: mirrorID)
        onStateChange()

        guard !suspendSyncEngineForTesting else { return }
        let plan = mirror.plan
        let retryPolicy = retryPolicyProvider()
        let operation = MirrorSyncOperation(
            plan: plan,
            stateStore: library.stateStore,
            runStore: library.runStore,
            driverFactory: { plan in
                MirrorSyncDriver(
                    plan: plan,
                    retryPolicy: retryPolicy,
                    mirrorRootDirectory: Constants.mirrorCacheDirectory
                )
            }
        )
        activeSyncOperations[mirrorID] = operation
        operation.confirmDestructivePush = { [weak self] destructivePlan, destination in
            guard let self else { return .cancel }
            return await self.requestDestructiveConfirmation(
                mirrorID: mirrorID,
                mirrorName: mirror.name,
                targetURL: destination.location.displayLocation,
                plan: destructivePlan
            )
        }
        operation.mirrorReleases = { [releaseMirrorService] plan, destination, log in
            try await releaseMirrorService.mirrorReleases(
                plan: plan,
                destination: destination,
                log: log
            )
        }
        operation.onEvent = { [weak self] event in
            guard let self, self.isCurrent(epoch: epoch, mirrorID: mirrorID) else { return }
            self.handleSyncEvent(event, plan: plan, mirrorID: mirrorID)
        }

        Task { [weak self] in
            do {
                try await operation.run()
            } catch {
                guard let self, self.isCurrent(epoch: epoch, mirrorID: mirrorID) else { return }
                self.finishSync(mirrorID: mirrorID)
                self.statuses[mirrorID] = .failed(error.localizedDescription)
                self.onError(error.localizedDescription)
                self.onStateChange()
            }
        }
    }

    private func handleSyncEvent(
        _ event: MirrorSyncOperationEvent,
        plan: MirrorPlan,
        mirrorID: UUID
    ) {
        switch event {
        case .activityChanged(let activity):
            if case .synchronizing(let phase, _) = activity {
                syncPhases[mirrorID] = phase
            }
        case .log(let line):
            liveSyncLogLines[mirrorID] = line
        case .persisted(let run, let snapshot):
            library.applyPersistedHealth(snapshot)
            appendInMemoryRecord(SyncRecord(run: run, plan: plan), mirrorID: mirrorID)
            finishSync(mirrorID: mirrorID)
            if run.outcome == .succeeded {
                statuses[mirrorID] = .idle
                onSyncCompletion(mirrorID, .succeeded)
            } else {
                let message = run.failure?.message
                    ?? snapshot.lastFailure?.message
                    ?? String.loc("Synchronization failed.")
                statuses[mirrorID] = .failed(message)
                onSyncCompletion(mirrorID, .failed(message))
            }
        }
        onStateChange()
    }

    private func startVerify(mirror: MirrorSnapshot) {
        let mirrorID = mirror.id
        let epoch = beginOperation(mirrorID: mirrorID)
        let plan = mirror.plan
        let operation = MirrorVerificationOperation(
            plan: plan,
            stateStore: library.stateStore,
            runStore: library.runStore
        )
        activeVerifiers[mirrorID] = operation
        inProgressVerifyIDs.insert(mirrorID)
        operation.onEvent = { [weak self] event in
            guard let self, self.isCurrent(epoch: epoch, mirrorID: mirrorID) else { return }
            guard case .persisted(let run, let snapshot) = event else { return }
            self.library.applyPersistedHealth(snapshot)
            self.appendInMemoryRecord(SyncRecord(run: run, plan: plan), mirrorID: mirrorID)
            self.finishVerify(mirrorID: mirrorID)
            switch snapshot.integrity {
            case .verified:
                if case .failed = self.statuses[mirrorID] {} else {
                    self.statuses[mirrorID] = .idle
                }
            case .diverged(let detail):
                self.statuses[mirrorID] = .diverged(detail)
            case .unknown, .inconclusive:
                break
            }
            self.onStateChange()
        }
        Task { [weak self] in
            do {
                try await operation.run()
            } catch {
                guard let self, self.isCurrent(epoch: epoch, mirrorID: mirrorID) else { return }
                self.finishVerify(mirrorID: mirrorID)
                self.onError(error.localizedDescription)
                self.onStateChange()
            }
        }
    }

    private func promoteQueuedSync(mirrorID: UUID) {
        guard let mirror = library.mirror(id: mirrorID) else {
            if let next = concurrencyGate.finishActive(mirrorID) {
                promoteQueuedSync(mirrorID: next)
            }
            return
        }
        startAdmittedSync(mirror: mirror)
    }

    private func finishSync(mirrorID: UUID) {
        denyPendingDestructiveConfirmation(for: mirrorID)
        inProgressSyncIDs.remove(mirrorID)
        activeSyncOperations.removeValue(forKey: mirrorID)
        syncPhases.removeValue(forKey: mirrorID)
        liveSyncLogLines.removeValue(forKey: mirrorID)
        onSyncSettled(mirrorID)
        if let next = concurrencyGate.finishActive(mirrorID) {
            promoteQueuedSync(mirrorID: next)
        }
    }

    private func finishVerify(mirrorID: UUID) {
        inProgressVerifyIDs.remove(mirrorID)
        activeVerifiers.removeValue(forKey: mirrorID)
    }

    private func appendInMemoryRecord(_ record: SyncRecord, mirrorID: UUID) {
        var existing = records[mirrorID] ?? []
        existing.append(record)
        if existing.count > 200 {
            existing.removeFirst(existing.count - 200)
        }
        records[mirrorID] = existing
    }

    private func requestDestructiveConfirmation(
        mirrorID: UUID,
        mirrorName: String,
        targetURL: String?,
        plan: DestructivePushPlan
    ) async -> DestructivePushDecision {
        denyPendingDestructiveConfirmation(for: mirrorID)
        onDestructiveConfirmationRequested()
        return await withCheckedContinuation { continuation in
            pendingDestructiveConfirmations.append(
                DestructivePushConfirmationRequest(
                    repoID: mirrorID,
                    repoName: mirrorName,
                    targetURL: targetURL,
                    plan: plan,
                    continuation: continuation
                )
            )
        }
    }

    private func denyPendingDestructiveConfirmation(for mirrorID: UUID) {
        let matching = pendingDestructiveConfirmations.filter { $0.repoID == mirrorID }
        pendingDestructiveConfirmations.removeAll { $0.repoID == mirrorID }
        matching.forEach { $0.respond(.cancel) }
    }

    private func resetStateFromLibrary() {
        statuses = Dictionary(uniqueKeysWithValues: library.mirrors.map {
            ($0.id, initialStatus(for: $0))
        })
        records = Dictionary(uniqueKeysWithValues: library.mirrors.map {
            ($0.id, [SyncRecord]())
        })
        syncPhases = [:]
        liveSyncLogLines = [:]
        inProgressSyncIDs = []
        inProgressVerifyIDs = []
        pendingDestructiveConfirmations = []
    }

    private func initialStatus(for mirror: MirrorSnapshot) -> SyncStatus {
        if mirror.needsCredentials {
            return .failed(MirrorCredentialGate.missingCredentialsMessage)
        }
        if let error = mirror.lastSyncError {
            return .failed(error)
        }
        if let detail = mirror.divergedDetail {
            return .diverged(detail)
        }
        return .unknown
    }

    private func beginOperation(mirrorID: UUID) -> Int {
        let epoch = (operationEpochs[mirrorID] ?? 0) + 1
        operationEpochs[mirrorID] = epoch
        return epoch
    }

    private func invalidateOperation(mirrorID: UUID) {
        operationEpochs[mirrorID] = (operationEpochs[mirrorID] ?? 0) + 1
    }

    private func isCurrent(epoch: Int, mirrorID: UUID) -> Bool {
        operationEpochs[mirrorID] == epoch
    }
}
