import Foundation

/// Which side of the mirror pair is missing when classification is repository-not-found.
enum RepoFailureSide: Equatable, Sendable {
    case source
    case destination
}

/// Primary next-step action for a recognized failure kind.
enum RepoFailurePrimaryAction: Equatable, Sendable {
    /// Opens the edit sheet focused on authentication fields.
    case reenterCredentials
}

/// Row / detail / menu-bar next steps derived from existing flags and classified messages.
/// Does not re-parse raw git stderr or change SyncEngine classification semantics.
struct RepoFailureNextStep: Equatable, Sendable {
    var primaryAction: RepoFailurePrimaryAction?
    /// When the failure is repository-not-found, whether it is src or dst.
    var missingRepositorySide: RepoFailureSide?
    /// Existing LFS install hint when a recent sync warned that git-lfs is missing.
    var missingGitLFSInstallHint: String?
    /// Secondary action: jump to the repo detail Sync Log.
    var showsOpenLog: Bool

    static let none = RepoFailureNextStep(
        primaryAction: nil,
        missingRepositorySide: nil,
        missingGitLFSInstallHint: nil,
        showsOpenLog: false
    )

    /// Short clarifying text for missing-repository failures (src vs dst).
    var missingRepositoryCaption: String? {
        switch missingRepositorySide {
        case .source:
            return String.loc("Source repository not found")
        case .destination:
            return String.loc("Destination repository not found")
        case nil:
            return nil
        }
    }

    var showsReenterCredentials: Bool {
        primaryAction == .reenterCredentials
    }

    static func make(
        repo: RepoConfig,
        status: SyncStatus,
        recentRecords: [SyncRecord] = []
    ) -> RepoFailureNextStep {
        let hasMissingGitLFS = LFSMirrorMessages.recentRecordsContainMissingToolWarning(recentRecords)
        let lfsHint = hasMissingGitLFS ? LFSMirrorMessages.installHint : nil

        if repo.needsCredentials {
            return RepoFailureNextStep(
                primaryAction: .reenterCredentials,
                missingRepositorySide: nil,
                missingGitLFSInstallHint: lfsHint,
                showsOpenLog: true
            )
        }

        if case .failed(let message) = status {
            if isMissingCredentialsMessage(message) {
                return RepoFailureNextStep(
                    primaryAction: .reenterCredentials,
                    missingRepositorySide: nil,
                    missingGitLFSInstallHint: lfsHint,
                    showsOpenLog: true
                )
            }

            let kind = SyncFailureClassifier.kind(fromStoredMessage: message)
            switch kind {
            case .authentication:
                // Auth failures get re-enter; LFS missing never drives the auth action.
                return RepoFailureNextStep(
                    primaryAction: .reenterCredentials,
                    missingRepositorySide: nil,
                    missingGitLFSInstallHint: nil,
                    showsOpenLog: true
                )
            case .repositoryNotFound:
                return RepoFailureNextStep(
                    primaryAction: nil,
                    missingRepositorySide: missingRepositorySide(
                        message: message,
                        recentRecords: recentRecords
                    ),
                    missingGitLFSInstallHint: nil,
                    showsOpenLog: true
                )
            case .network, .pushRejected, .other:
                return RepoFailureNextStep(
                    primaryAction: nil,
                    missingRepositorySide: nil,
                    missingGitLFSInstallHint: lfsHint,
                    showsOpenLog: true
                )
            }
        }

        // Successful (or idle) sync that still warned about missing git-lfs — show install hint on the row.
        if hasMissingGitLFS {
            return RepoFailureNextStep(
                primaryAction: nil,
                missingRepositorySide: nil,
                missingGitLFSInstallHint: lfsHint,
                showsOpenLog: !recentRecords.isEmpty
            )
        }

        return .none
    }

    // MARK: - Side detection (from existing records / classified messages)

    static func missingRepositorySide(
        message: String,
        recentRecords: [SyncRecord]
    ) -> RepoFailureSide {
        if let record = recentRecords.last(where: { !$0.succeeded }) {
            let failedNotFound = record.targetResults.filter { result in
                guard !result.succeeded, let error = result.error else { return false }
                return SyncFailureClassifier.kind(fromStoredMessage: error) == .repositoryNotFound
            }
            if !failedNotFound.isEmpty {
                return .destination
            }
            // Source clone/fetch failures finish with empty targetResults.
            if record.targetResults.isEmpty {
                return .source
            }
        }

        let lower = message.lowercased()
        if lower.contains("targets failed") {
            return .destination
        }
        if let notFound = SyncFailureClassifier.displayMessage(for: .repositoryNotFound) {
            // Aggregate / per-target: "https://…: Repository not found — check URL"
            if message != notFound, lower.contains(notFound.lowercased()) {
                return .destination
            }
        }
        return .source
    }

    // MARK: - Helpers

    private static func isMissingCredentialsMessage(_ message: String) -> Bool {
        message == RepoCredentialGate.missingCredentialsMessage
    }
}
