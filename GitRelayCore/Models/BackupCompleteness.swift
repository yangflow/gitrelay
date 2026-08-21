import Foundation

/// Whether a configured mirror is a full backup, derived from existing repo flags
/// and recent sync log lines already used by the detail-pane warnings.
///
/// Does **not** treat `needsCredentials` (imported, awaiting auth) as incomplete.
struct BackupCompleteness: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        /// `depth` is set — history is truncated.
        case shallowClone
        /// Fetch refspecs differ from the default heads+tags mirror set.
        case customRefFilters
        /// A recent sync warned that the source uses Git LFS but `git-lfs` was missing.
        case missingGitLFSTool
    }

    /// Ordered reasons that make this mirror incomplete. Empty means a full mirror.
    let reasons: [Reason]

    var isComplete: Bool { reasons.isEmpty }

    /// Visible mark for sidebar / menu-bar rows.
    var showsIncompleteMark: Bool { !isComplete }

    /// Help / accessibility copy describing what is missing.
    var helpText: String? {
        guard !reasons.isEmpty else { return nil }
        let detail = reasons.map(\.missingDetail).joined(separator: "; ")
        return String(localized: "Incomplete backup: \(detail)")
    }

    static func evaluate(
        repo: RepoConfig,
        recentRecords: [SyncRecord] = []
    ) -> BackupCompleteness {
        var reasons: [Reason] = []

        if repo.isShallowClone {
            reasons.append(.shallowClone)
        }
        if !RepoConfig.refSpecsEqual(repo.resolvedRefSpecs, RepoConfig.defaultRefSpecs) {
            reasons.append(.customRefFilters)
        }
        if LFSMirrorMessages.recentRecordsContainMissingToolWarning(recentRecords) {
            reasons.append(.missingGitLFSTool)
        }

        return BackupCompleteness(reasons: reasons)
    }
}

extension BackupCompleteness.Reason {
    /// Phrase naming what is missing (joined into the incomplete-backup help string).
    var missingDetail: String {
        switch self {
        case .shallowClone:
            return String(localized: "shallow clone (history truncated)")
        case .customRefFilters:
            return String(localized: "custom ref filters (only selected refs sync)")
        case .missingGitLFSTool:
            return String(localized: "git-lfs missing while the source uses Git LFS")
        }
    }
}
