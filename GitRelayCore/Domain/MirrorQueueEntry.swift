import Foundation

/// A repository currently occupying, or waiting for, a sync slot.
///
/// Derived entirely from the existing statuses and phases published by
/// `MirrorOperationsController`; list projections never drive sync themselves.
nonisolated struct MirrorQueueEntry: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        /// Git is running. `caption` is the parsed phase text, never raw stderr.
        case syncing(caption: String)
        case queued

        var isSyncing: Bool {
            if case .syncing = self { return true }
            return false
        }

        var title: String {
            switch self {
            case .syncing(let caption):
                return caption
            case .queued:
                return String(localized: "Queued")
            }
        }
    }

    let id: UUID
    let name: String
    let provider: GitProvider?
    let state: State
}

nonisolated enum MirrorQueueProjection {
    /// Syncing repositories first, then queued ones, each in configured order.
    static func entries(
        repos: [MirrorSnapshot],
        statuses: [UUID: SyncStatus],
        syncPhases: [UUID: SyncPhase]
    ) -> [MirrorQueueEntry] {
        var syncing: [MirrorQueueEntry] = []
        var queued: [MirrorQueueEntry] = []

        for repo in repos {
            let provider = GitRemoteHost.inferredProvider(fromRemoteURL: repo.srcURL)
            switch statuses[repo.id] ?? .unknown {
            case .syncing:
                let caption = syncPhases[repo.id]?.displayCaption ?? String(localized: "Syncing...")
                syncing.append(
                    MirrorQueueEntry(
                        id: repo.id,
                        name: repo.name,
                        provider: provider,
                        state: .syncing(caption: caption)
                    )
                )
            case .queued:
                queued.append(
                    MirrorQueueEntry(
                        id: repo.id,
                        name: repo.name,
                        provider: provider,
                        state: .queued
                    )
                )
            case .unknown, .idle, .ahead, .diverged, .failed:
                continue
            }
        }

        return syncing + queued
    }
}
