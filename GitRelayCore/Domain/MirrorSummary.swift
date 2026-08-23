import Foundation

/// Condensed status shown in the 源 / 目标 / 状态 / 上次 pair table.
///
/// The table deliberately collapses to a green check or a red dot; content
/// divergence reads as a failure rather than its own caution glyph.
nonisolated enum MirrorSummaryStatusKind: String, Equatable, Sendable {
    case succeeded
    case failed
    case syncing
    case queued
    case notSynced

    var title: String {
        switch self {
        case .succeeded:
            String(localized: "Succeeded")
        case .failed:
            String(localized: "Failed")
        case .syncing:
            String(localized: "Syncing...")
        case .queued:
            String(localized: "Queued")
        case .notSynced:
            String(localized: "Not Synced")
        }
    }

    var systemImage: String {
        switch self {
        case .succeeded:
            "checkmark.circle.fill"
        case .failed:
            "circle.fill"
        case .syncing:
            "arrow.triangle.2.circlepath"
        case .queued:
            "clock"
        case .notSynced:
            "minus.circle"
        }
    }
}

/// Compact presentation used by mirror detail and aggregate summaries.
nonisolated struct MirrorSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// `owner/repo` when the remote parses, otherwise the raw URL.
    let sourceLabel: String
    let sourceURL: String
    let sourceProvider: GitProvider?
    /// `host/owner/repo` for git remotes, or the archive path for filesystem targets.
    let targetLabel: String
    let targetURL: String
    let targetProvider: GitProvider?
    /// Enabled targets beyond the first, shown as a `+N` affordance.
    let additionalTargetCount: Int
    let status: MirrorSummaryStatusKind
    /// Failure or divergence text for help / accessibility. Never a credential.
    let statusDetail: String?
    let lastSyncedAt: Date?

    var lastSyncedText: String? {
        lastSyncedAt?.formatted(.relative(presentation: .named))
    }
}

nonisolated enum MirrorSummaryProjection {
    static func rows(
        repos: [MirrorSnapshot],
        statuses: [UUID: SyncStatus]
    ) -> [MirrorSummary] {
        repos.map { row(for: $0, status: statuses[$0.id] ?? .unknown) }
    }

    static func row(for repo: MirrorSnapshot, status: SyncStatus) -> MirrorSummary {
        let enabled = repo.enabledTargets
        let primary = enabled.first ?? repo.targets.first
        return MirrorSummary(
            id: repo.id,
            name: repo.name,
            sourceLabel: sourceLabel(for: repo.srcURL),
            sourceURL: repo.srcURL,
            sourceProvider: GitRemoteHost.inferredProvider(fromRemoteURL: repo.srcURL),
            targetLabel: primary.map(targetLabel(for:)) ?? "",
            targetURL: primary?.displayLabel ?? "",
            targetProvider: primary.flatMap(targetProvider(for:)),
            additionalTargetCount: max(0, enabled.count - 1),
            status: statusKind(for: repo, status: status),
            statusDetail: statusDetail(for: repo, status: status),
            lastSyncedAt: repo.lastSyncedAt
        )
    }

    static func sourceLabel(for remoteURL: String) -> String {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path = GitRemoteRepoPath.parse(from: trimmed) else { return trimmed }
        return path.pathWithNamespace
    }

    /// Targets carry the host so a mirror to a different forge is obvious at a glance.
    static func targetLabel(for target: MirrorTarget) -> String {
        switch target.kind {
        case .filesystem:
            return target.displayLabel
        case .gitRemote:
            let trimmed = target.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path = GitRemoteRepoPath.parse(from: trimmed) else { return trimmed }
            guard let host = GitRemoteHost.host(from: trimmed) else { return path.pathWithNamespace }
            return "\(host)/\(path.pathWithNamespace)"
        }
    }

    static func targetProvider(for target: MirrorTarget) -> GitProvider? {
        switch target.kind {
        case .filesystem:
            return nil
        case .gitRemote:
            return GitRemoteHost.inferredProvider(fromRemoteURL: target.url)
        }
    }

    static func statusKind(for repo: MirrorSnapshot, status: SyncStatus) -> MirrorSummaryStatusKind {
        switch status {
        case .syncing:
            return .syncing
        case .queued:
            return .queued
        case .failed, .diverged:
            return .failed
        case .idle, .ahead:
            return .succeeded
        case .unknown:
            if repo.needsCredentials || repo.lastSyncError != nil || repo.isDiverged {
                return .failed
            }
            return repo.lastSuccessfulSyncedAt == nil ? .notSynced : .succeeded
        }
    }

    static func statusDetail(for repo: MirrorSnapshot, status: SyncStatus) -> String? {
        switch status {
        case .failed(let message):
            return message
        case .diverged(let detail):
            return detail
        case .idle, .ahead, .syncing, .queued:
            return nil
        case .unknown:
            return repo.lastSyncError ?? repo.divergedDetail
        }
    }
}
