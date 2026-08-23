import Foundation
import Observation

/// Owns the persisted mirror library and its application-facing projection.
///
/// Feature controllers may ask this model for the stores needed by an
/// operation, but views never access persistence directly. Configuration and
/// compact health remain separate on disk and are committed together here.
@MainActor
@Observable
final class MirrorLibraryModel {
    private(set) var plans: [MirrorPlan] = []
    private(set) var healthSnapshots: [UUID: MirrorHealthSnapshot] = [:]
    private(set) var mirrors: [MirrorSnapshot] = []
    private(set) var lastErrorMessage: String?

    @ObservationIgnored
    let planStore: MirrorPlanStore
    @ObservationIgnored
    let stateStore: MirrorStateStore
    @ObservationIgnored
    let runStore: MirrorRunStore

    init(
        planStore: MirrorPlanStore = MirrorPlanStore(),
        stateStore: MirrorStateStore = MirrorStateStore(),
        runStore: MirrorRunStore = MirrorRunStore(),
        credentialProbe: CredentialProbe = .live
    ) {
        self.planStore = planStore
        self.stateStore = stateStore
        self.runStore = runStore
        load(credentialProbe: credentialProbe)
    }

    func mirror(id: UUID) -> MirrorSnapshot? {
        mirrors.first(where: { $0.id == id })
    }

    func add(_ mirror: MirrorSnapshot) throws {
        try add(contentsOf: [mirror])
    }

    func add(contentsOf additions: [MirrorSnapshot]) throws {
        guard !additions.isEmpty else { return }
        try commit(mirrors + additions, preservePersistedHealth: true)
    }

    func update(_ mirror: MirrorSnapshot) throws {
        guard let index = mirrors.firstIndex(where: { $0.id == mirror.id }) else {
            throw MirrorLibraryError.mirrorNotFound(mirror.id)
        }
        var next = mirrors
        next[index] = mirror
        try commit(next, preservePersistedHealth: true)
    }

    func mutateMirror(
        id: UUID,
        _ transform: (inout MirrorSnapshot) throws -> Void
    ) throws {
        guard let index = mirrors.firstIndex(where: { $0.id == id }) else {
            throw MirrorLibraryError.mirrorNotFound(id)
        }
        var next = mirrors
        try transform(&next[index])
        try commit(next, preservePersistedHealth: true)
    }

    @discardableResult
    func remove(id: UUID) throws -> MirrorSnapshot? {
        guard let removed = mirrors.first(where: { $0.id == id }) else { return nil }
        try commit(mirrors.filter { $0.id != id }, preservePersistedHealth: true)
        try? FileManager.default.removeItem(at: runStore.fileURL(for: id))
        return removed
    }

    /// Replaces the in-memory and persisted application library in one commit.
    /// Import callers choose whether health for matching IDs may be retained.
    func replace(
        with replacements: [MirrorSnapshot],
        preservePersistedHealth: Bool
    ) throws {
        try commit(replacements, preservePersistedHealth: preservePersistedHealth)
    }

    /// Updates the application projection after an operation has already
    /// persisted its authoritative run record and compact health snapshot.
    func applyPersistedHealth(_ snapshot: MirrorHealthSnapshot) {
        healthSnapshots[snapshot.mirrorID] = snapshot
        guard let index = mirrors.firstIndex(where: { $0.id == snapshot.mirrorID }) else { return }
        mirrors[index].health = snapshot
    }

    /// Credential readiness is machine-local derived state and is never saved
    /// into the plan or compact health document.
    @discardableResult
    func refreshCredentialRequirements(probe: CredentialProbe = .live) -> Set<UUID> {
        var changed = Set<UUID>()
        for index in mirrors.indices {
            let needsCredentials = MirrorCredentialGate.needsCredentials(
                for: mirrors[index].plan,
                probe: probe
            )
            guard mirrors[index].needsCredentials != needsCredentials else { continue }
            mirrors[index].needsCredentials = needsCredentials
            changed.insert(mirrors[index].id)
        }
        return changed
    }

    func markNeedsCredentials(_ needsCredentials: Bool, mirrorID: UUID) {
        guard let index = mirrors.firstIndex(where: { $0.id == mirrorID }) else { return }
        mirrors[index].needsCredentials = needsCredentials
    }

    func loadRuns(mirrorID: UUID) throws -> [MirrorRunRecord] {
        try runStore.load(mirrorID: mirrorID)
    }

    private func load(credentialProbe: CredentialProbe) {
        do {
            plans = try planStore.load()
        } catch {
            plans = []
            lastErrorMessage = String(
                format: String.loc("Failed to load mirror configuration: %@"),
                error.localizedDescription
            )
        }

        do {
            healthSnapshots = try stateStore.load()
        } catch {
            // Health is rebuildable. A damaged state file must not hide valid
            // plans from the library.
            healthSnapshots = [:]
            lastErrorMessage = String(
                format: String.loc("Failed to load mirror status: %@"),
                error.localizedDescription
            )
        }

        mirrors = plans.map { plan in
            MirrorSnapshot(
                plan: plan,
                health: healthSnapshots[plan.id],
                needsCredentials: MirrorCredentialGate.needsCredentials(
                    for: plan,
                    probe: credentialProbe
                )
            )
        }
    }

    private func commit(
        _ proposedMirrors: [MirrorSnapshot],
        preservePersistedHealth: Bool
    ) throws {
        do {
            let nextPlans = try proposedMirrors.map {
                try $0.plan.validated(allowMissingCredentials: true)
            }

            // A CLI or other headless operation may have updated health while
            // the app was open. Merge from disk inside this application commit
            // so a metadata edit cannot erase that newer state.
            let persistedHealth = try stateStore.load()
            let knownIDs = Set(proposedMirrors.map(\.id))
            var nextHealth = preservePersistedHealth
                ? persistedHealth.filter { knownIDs.contains($0.key) }
                : [:]
            for mirror in proposedMirrors {
                nextHealth[mirror.id] = freshestHealth(
                    mirror.health,
                    preservePersistedHealth ? healthSnapshots[mirror.id] : nil,
                    preservePersistedHealth ? persistedHealth[mirror.id] : nil
                )
            }

            let previousPlans = try planStore.load()
            do {
                try planStore.save(nextPlans)
                try stateStore.save(nextHealth)
            } catch {
                // Until Phase 2 introduces a generation manifest, restore the
                // previous pair if the second atomic document write fails.
                try? planStore.save(previousPlans)
                try? stateStore.save(persistedHealth)
                throw error
            }

            plans = nextPlans
            healthSnapshots = nextHealth
            mirrors = proposedMirrors.map { proposed in
                var projected = proposed
                projected.plan = nextPlans.first(where: { $0.id == proposed.id }) ?? proposed.plan
                projected.health = nextHealth[proposed.id]
                    ?? MirrorHealthSnapshot(mirrorID: proposed.id)
                return projected
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(
                format: String.loc("Failed to save mirror configuration: %@"),
                error.localizedDescription
            )
            throw error
        }
    }

    private func freshestHealth(
        _ candidates: MirrorHealthSnapshot?...
    ) -> MirrorHealthSnapshot? {
        candidates.compactMap { $0 }.max { lhs, rhs in
            healthAnchor(lhs) < healthAnchor(rhs)
        }
    }

    private func healthAnchor(_ snapshot: MirrorHealthSnapshot) -> Date {
        [snapshot.lastAttemptAt, snapshot.lastVerifiedAt]
            .compactMap { $0 }
            .max() ?? .distantPast
    }
}

enum MirrorLibraryError: LocalizedError, Equatable {
    case mirrorNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .mirrorNotFound(let mirrorID):
            String(format: String.loc("No mirror with ID %@ was found."), mirrorID.uuidString)
        }
    }
}
