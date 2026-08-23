import Foundation
import Observation

/// What the preflight needs from the add sheet's two fields. A value type, so a
/// debounced probe can tell whether the answer it came back with still matches
/// what the user has typed since.
nonisolated struct AddPreflightInput: Equatable, Sendable {
    var sourceURL: String = ""
    var sourceCredentials: RemoteProbeCredentials = RemoteProbeCredentials()
    var destinationURL: String = ""
    var destinationCredentials: RemoteProbeCredentials = RemoteProbeCredentials()
    /// Archive targets go to the filesystem — there is no remote to ask.
    var destinationIsFilesystem: Bool = false

    var probesSource: Bool {
        Self.namesARepository(sourceURL)
    }

    var probesDestination: Bool {
        !destinationIsFilesystem && Self.namesARepository(destinationURL)
    }

    /// Both an owner and a repository name, so a half-typed URL is never
    /// reported as missing — and never offered up for creation.
    private static func namesARepository(_ url: String) -> Bool {
        guard let host = GitRemoteHost.host(from: url), !host.isEmpty,
              let path = GitRemoteRepoPath.parse(from: url)
        else { return false }
        return !path.namespace.isEmpty && !path.name.isEmpty
    }
}

/// Preflight for the short-path add sheet: probe both URLs after the typing
/// settles, notice a duplicate pair locally, and offer to create a missing
/// destination. Everything it has to say goes into one quiet caption line, and
/// nothing here blocks typing or the Cancel button.
@MainActor
@Observable
final class AddRepoPreflightViewModel {
    private(set) var decision: AddPreflightDecision = .idle
    private(set) var isProbing = false
    private(set) var isCreatingDestination = false

    /// Set when a create attempt has something to say; takes over the same line.
    private(set) var actionMessage: String?

    private var input = AddPreflightInput()
    private var sourceResult: AddPreflightProbeResult = .pending
    private var destinationResult: AddPreflightProbeResult = .pending
    private var duplicateRepoID: UUID?
    private var isFinished = false

    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private let probe: any RemoteExistenceProbing
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let destinationPlan: @MainActor (String) -> DestinationRepoPlan?

    init(
        probe: any RemoteExistenceProbing = GitRemoteExistenceProbe(),
        debounce: Duration = .milliseconds(600),
        destinationPlan: @MainActor @escaping (String) -> DestinationRepoPlan? = {
            DestinationRepoPlan.make(destinationURL: $0)
        }
    ) {
        self.probe = probe
        self.debounce = debounce
        self.destinationPlan = destinationPlan
    }

    // MARK: - Presentation

    /// The one line under the two fields.
    var caption: String? {
        if let actionMessage { return actionMessage }
        if isCreatingDestination { return AddPreflightCopy.creatingDestinationCaption }
        if let line = AddPreflightCopy.caption(for: decision, destinationURL: input.destinationURL) {
            return line
        }
        if isProbing { return AddPreflightCopy.checkingCaption }
        return nil
    }

    var primaryAction: AddPreflightPrimaryAction {
        decision.primaryAction
    }

    var offersOpenExistingPair: Bool {
        decision.offersOpenExistingPair
    }

    var existingPairID: UUID? {
        decision.existingPairID
    }

    // MARK: - Input

    /// Called as the user types or pastes. The duplicate check answers at once;
    /// the network probes wait for the typing to settle.
    func update(
        _ newInput: AddPreflightInput,
        existingRepos: [MirrorSnapshot],
        excluding excludedID: UUID? = nil
    ) {
        guard !isFinished else { return }
        let previous = input
        input = newInput
        actionMessage = nil
        duplicateRepoID = MirrorPairDuplicates.existingRepoID(
            source: newInput.sourceURL,
            target: newInput.destinationURL,
            in: existingRepos,
            excluding: excludedID
        )

        if duplicateRepoID != nil {
            // A known pair needs no network round trip to explain itself.
            probeTask?.cancel()
            probeTask = nil
            isProbing = false
            recompute()
            return
        }

        guard newInput != previous else {
            recompute()
            return
        }

        sourceResult = newInput.probesSource ? .pending : .skipped
        destinationResult = newInput.probesDestination ? .pending : .skipped
        recompute()
        scheduleProbe()
    }

    func cancel() {
        probeTask?.cancel()
        probeTask = nil
        isProbing = false
    }

    /// The pair is being saved: stop probing and stop reacting, so the sheet
    /// cannot flash "already exists" at the repository it is adding right now.
    func finish() {
        isFinished = true
        cancel()
    }

    /// Runs the probes without the debounce wait (tests, and the create path).
    func probeNow() async {
        probeTask?.cancel()
        probeTask = nil
        await runProbes(for: input)
    }

    // MARK: - Create the missing destination

    /// Creates the empty destination repository when that is what the primary
    /// button promised. Returns true when the sheet may save and start syncing.
    func prepareDestinationForSave() async -> Bool {
        guard decision == .destinationMissing else { return true }
        actionMessage = nil

        guard let plan = destinationPlan(input.destinationURL), plan.hasToken else {
            actionMessage = AddPreflightCopy.missingCreateTokenCaption(
                destinationURL: input.destinationURL
            )
            return false
        }

        isCreatingDestination = true
        defer { isCreatingDestination = false }

        do {
            _ = try await plan.createEmptyRepo()
            destinationResult = .reachable
            recompute()
            return true
        } catch {
            let message = (error as? TargetProviderAPIError)?.errorDescription
                ?? error.localizedDescription
            actionMessage = AddPreflightCopy.createFailedCaption(
                SyncEngine.redactCredentials(message)
            )
            return false
        }
    }

    // MARK: - Private

    private func scheduleProbe() {
        probeTask?.cancel()
        let target = input
        let delay = debounce
        probeTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.runProbes(for: target)
        }
    }

    private func runProbes(for target: AddPreflightInput) async {
        guard target == input, duplicateRepoID == nil else { return }
        guard target.probesSource || target.probesDestination else {
            recompute()
            return
        }

        isProbing = true
        let prober = probe
        let plan = target.probesDestination ? destinationPlan(target.destinationURL) : nil

        async let source = Self.sourceResult(for: target, probe: prober)
        async let destination = Self.destinationResult(for: target, probe: prober, plan: plan)
        let results = await (source, destination)

        isProbing = false
        guard target == input, duplicateRepoID == nil else { return }
        sourceResult = results.0
        destinationResult = results.1
        recompute()
    }

    private nonisolated static func sourceResult(
        for target: AddPreflightInput,
        probe: any RemoteExistenceProbing
    ) async -> AddPreflightProbeResult {
        guard target.probesSource else { return .skipped }
        return await probe.probe(url: target.sourceURL, credentials: target.sourceCredentials)
    }

    /// Prefers the destination host's API, which separates "no such repository"
    /// from "credentials refused"; falls back to git when no token covers it.
    private nonisolated static func destinationResult(
        for target: AddPreflightInput,
        probe: any RemoteExistenceProbing,
        plan: DestinationRepoPlan?
    ) async -> AddPreflightProbeResult {
        guard target.probesDestination else { return .skipped }
        if let plan, plan.hasToken {
            let apiResult = await plan.probeExistence()
            if apiResult != .skipped {
                return apiResult
            }
        }
        return await probe.probe(url: target.destinationURL, credentials: target.destinationCredentials)
    }

    private func recompute() {
        decision = AddPreflight.decide(
            source: sourceResult,
            destination: destinationResult,
            duplicateRepoID: duplicateRepoID
        )
    }
}
