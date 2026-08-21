import Foundation

/// Which half of a mirror pair a preflight answer refers to.
nonisolated enum AddPreflightSide: String, Equatable, Sendable {
    case source
    case destination
}

/// What one preflight probe learned about one URL.
nonisolated enum AddPreflightProbeResult: Equatable, Sendable {
    /// The remote answered and the repository is there (an empty repository counts).
    case reachable
    /// The host answered that there is no such repository.
    case missing
    /// The host refused the token, key, or account.
    case authenticationFailed
    /// Network, DNS, or timeout — nothing learned about the repository itself.
    case unreachable
    /// Nothing to probe: blank field, archive target, or local path.
    case skipped
    /// Probe still running, or not started yet.
    case pending
}

/// The single quiet line the add sheet shows under the two fields, and the
/// primary action that goes with it. One state at a time — never a banner stack.
nonisolated enum AddPreflightDecision: Equatable, Sendable {
    /// Not enough answered yet to say anything.
    case idle
    /// Both sides answered and the pair is new.
    case ready
    case duplicatePair(existingRepoID: UUID)
    case destinationMissing
    case sourceMissing
    case authenticationFailed(AddPreflightSide)
    case unreachable(AddPreflightSide)
}

nonisolated enum AddPreflight {
    /// Resolves the two probe answers plus the local duplicate check into one state.
    ///
    /// Order matters and is deliberate: a duplicate is a local fact that needs no
    /// network, a refused credential explains any later answer, and a missing
    /// destination is the only state that offers to create something.
    static func decide(
        source: AddPreflightProbeResult,
        destination: AddPreflightProbeResult,
        duplicateRepoID: UUID? = nil
    ) -> AddPreflightDecision {
        if let duplicateRepoID {
            return .duplicatePair(existingRepoID: duplicateRepoID)
        }
        if source == .authenticationFailed {
            return .authenticationFailed(.source)
        }
        if destination == .authenticationFailed {
            return .authenticationFailed(.destination)
        }
        if destination == .missing {
            return .destinationMissing
        }
        if source == .missing {
            return .sourceMissing
        }
        if source == .unreachable {
            return .unreachable(.source)
        }
        if destination == .unreachable {
            return .unreachable(.destination)
        }
        if source == .pending || destination == .pending {
            return .idle
        }
        return .ready
    }
}

/// What the prominent footer button does in a given preflight state.
nonisolated enum AddPreflightPrimaryAction: Equatable, Sendable {
    /// Save the pair and start the first sync.
    case add
    /// Create the empty destination repository first, then save and sync.
    case createDestination
    /// Save a second pair with the same two URLs.
    case addAnyway
}

extension AddPreflightDecision {
    var primaryAction: AddPreflightPrimaryAction {
        switch self {
        case .duplicatePair:
            return .addAnyway
        case .destinationMissing:
            return .createDestination
        case .idle, .ready, .sourceMissing, .authenticationFailed, .unreachable:
            return .add
        }
    }

    /// Duplicate is the only state that swaps the secondary button for
    /// "open the existing one" (the locked mockup drops 更多选项 there).
    var offersOpenExistingPair: Bool {
        existingPairID != nil
    }

    var existingPairID: UUID? {
        if case .duplicatePair(let id) = self { return id }
        return nil
    }

    /// True while the sheet has something quiet to say under the fields.
    var hasCaption: Bool {
        switch self {
        case .idle, .ready:
            return false
        case .duplicatePair, .destinationMissing, .sourceMissing, .authenticationFailed, .unreachable:
            return true
        }
    }
}
